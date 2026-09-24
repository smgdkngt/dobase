//! A chat: messages by day, refreshed every few seconds, and a line to write in.

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use serde_json::{Value, json};

use crate::command::{Result, bytes, paragraphs};
use crate::tui::app::{App, Fx, Job, Tone};
use crate::tui::screens::Screen;
use crate::tui::theme;
use crate::tui::widgets::{TextInput, local, panel, wrap};
use crate::value::Json;

pub const HELP: [(&str, &str); 8] = [
    ("i / enter", "Write a message"),
    ("enter", "Send it (while writing)"),
    ("esc", "Stop writing; again to go home"),
    ("↑ ↓ / j k", "Scroll"),
    ("end / G", "Jump to the newest message"),
    ("+", "Put a 👍 on the newest message"),
    ("o", "Open the chat in your browser"),
    ("r", "Reload (it also reloads by itself)"),
];

pub struct Chat {
    pub tool: Value,
    messages: Vec<Value>,
    input: TextInput,
    writing: bool,
    /// Lines scrolled up from the newest message.
    scroll: usize,
}

impl Chat {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        let messages = fetch(app, &tool)?;
        Ok(Self { tool, messages, input: TextInput::default(), writing: false, scroll: 0 })
    }

    pub fn typing(&self) -> bool {
        self.writing
    }

    pub fn hints(&self) -> Vec<(&'static str, &'static str)> {
        if self.writing {
            vec![("enter", "send"), ("esc", "stop writing")]
        } else {
            vec![("i", "write"), ("↑↓", "scroll"), ("+", "👍 newest"), ("esc", "home")]
        }
    }

    /// Reloads the messages, keeping what you're writing.
    pub fn refresh(&self) -> Job {
        let tool = self.tool.clone();
        Box::new(move |app: &mut App| {
            let messages = fetch(app, &tool)?;
            if let Screen::Chat(chat) = &mut app.screen {
                chat.messages = messages;
            }
            Ok(())
        })
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        if self.writing {
            match key.code {
                KeyCode::Esc => self.writing = false,
                KeyCode::Enter => {
                    if !self.input.is_blank() {
                        let text = self.input.text().trim().to_string();
                        self.input.clear();
                        self.scroll = 0;
                        let tool = self.tool["id"].int();
                        fx.job("Sending", move |app| {
                            app.post(&format!("/tools/{tool}/chat/messages"), json!({ "message": { "body": paragraphs(&text) } }))?;
                            reload(app)
                        });
                    }
                }
                _ => {
                    self.input.key(key);
                }
            }
            return true;
        }

        match key.code {
            KeyCode::Char('i') | KeyCode::Enter | KeyCode::Char('c') => self.writing = true,
            KeyCode::Up | KeyCode::Char('k') => self.scroll += 1,
            KeyCode::Down | KeyCode::Char('j') => self.scroll = self.scroll.saturating_sub(1),
            KeyCode::PageUp => self.scroll += 10,
            KeyCode::PageDown => self.scroll = self.scroll.saturating_sub(10),
            KeyCode::End | KeyCode::Char('G') => self.scroll = 0,
            KeyCode::Char('+') => {
                if let Some(message) = self.messages.last() {
                    let (tool, id) = (self.tool["id"].int(), message["id"].int());
                    let author = message["user"]["name"].opt().unwrap_or_else(|| "someone".into());
                    fx.job("Reacting", move |app| {
                        app.post(&format!("/tools/{tool}/chat/messages/{id}/reactions"), json!({ "emoji": "👍" }))?;
                        reload(app)?;
                        app.toast(format!("👍 for {author}"), Tone::Success);
                        Ok(())
                    });
                }
            }
            _ => return false,
        }
        true
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        let [messages_area, input_area] = Layout::vertical([Constraint::Min(3), Constraint::Length(3)]).areas(area);
        let block = panel(format!("{} {}", theme::tool_icon("chat"), self.tool["name"].s()), !self.writing);
        let inner = block.inner(messages_area);
        frame.render_widget(block, messages_area);

        let lines = self.lines(usize::from(inner.width.saturating_sub(2)));
        if lines.is_empty() {
            frame.render_widget(Paragraph::new("It's quiet in here. Press i and say hi 👋").style(theme::dim()), inner);
        } else {
            let height = usize::from(inner.height);
            self.scroll = self.scroll.min(lines.len().saturating_sub(height));
            let end = lines.len() - self.scroll;
            let start = end.saturating_sub(height);
            let visible: Vec<Line> = lines[start..end].to_vec();
            // Keep the newest message at the bottom, like a chat does.
            let pad = height.saturating_sub(visible.len()) as u16;
            let area = Rect { y: inner.y + pad, height: inner.height - pad, ..inner };
            frame.render_widget(Paragraph::new(visible), area.inner(ratatui::layout::Margin { horizontal: 1, vertical: 0 }));
            if self.scroll > 0 {
                let note = Span::styled(format!(" ↓ {} newer lines · G to jump ", self.scroll), Style::new().fg(theme::accent()));
                frame.render_widget(Line::from(note).right_aligned(), Rect { y: messages_area.bottom() - 1, height: 1, ..messages_area });
            }
        }

        let input_block = panel(if self.writing { "Message · enter to send" } else { "Press i to write" }, self.writing);
        let field = input_block.inner(input_area);
        frame.render_widget(input_block, input_area);
        let field = Rect { x: field.x + 1, width: field.width.saturating_sub(2), ..field };
        self.input.render(frame, field, if self.writing { "Say something nice…" } else { "" }, self.writing);
    }

    /// Every message as lines, oldest first, with a divider for each day.
    fn lines(&self, width: usize) -> Vec<Line<'static>> {
        let mut lines = Vec::new();
        let mut day = None;
        let mut previous: Option<(String, jiff::Zoned)> = None;
        for message in &self.messages {
            let Some(created) = local(&message["created_at"]) else { continue };
            if day != Some(created.date()) {
                day = Some(created.date());
                previous = None;
                let label = if created.date() == jiff::Zoned::now().date() {
                    "Today".to_string()
                } else {
                    created.strftime("%A %-d %B").to_string()
                };
                let rule = "─".repeat(width.saturating_sub(label.chars().count() + 2) / 2);
                lines.push(Line::raw(""));
                lines.push(Line::from(Span::styled(format!("{rule} {label} {rule}"), theme::dim())).centered());
            }

            // A name heads each run of messages by one person, and again after a pause.
            let author = message["user"]["name"].opt().unwrap_or_else(|| "Former member".to_string());
            let continues = previous
                .as_ref()
                .is_some_and(|(name, at)| *name == author && created.timestamp().duration_since(at.timestamp()).as_secs() < 5 * 60);
            if !continues {
                lines.push(Line::raw(""));
                let edited = if message["edited_at"].truthy() { " (edited)" } else { "" };
                lines.push(Line::from(vec![
                    Span::styled(author.clone(), Style::new().fg(theme::person_color(&author)).add_modifier(Modifier::BOLD)),
                    Span::styled(format!(" {}{edited}", created.strftime("%H:%M")), theme::dim()),
                ]));
            }
            previous = Some((author, created));
            if message["reply_to"].truthy() {
                let reply = format!("↳ {}: {}", message["reply_to"]["user_name"].s(), message["reply_to"]["preview"].s());
                lines.push(Line::from(Span::styled(
                    crate::tui::widgets::truncate(&reply, width),
                    theme::dim().add_modifier(Modifier::ITALIC),
                )));
            }
            for line in wrap(&crate::command::clean(message["body"].s().trim()), width) {
                lines.push(Line::raw(line));
            }
            for file in message["files"].items() {
                lines.push(Line::from(Span::styled(format!("📎 {} ({})", file["filename"].s(), bytes(&file["byte_size"])), theme::dim())));
            }
            let reactions: Vec<String> = message["reactions"]
                .items()
                .iter()
                .map(|reaction| format!("{} {}", reaction["emoji"].s(), reaction["users"].items().len()))
                .collect();
            if !reactions.is_empty() {
                lines.push(Line::from(Span::styled(reactions.join("  "), Style::new().fg(theme::warning()))));
            }
        }
        lines
    }
}

fn fetch(app: &mut App, tool: &Value) -> Result<Vec<Value>> {
    let chat = app.get(&format!("/tools/{}/chat", tool["id"].s()), &[("limit", "100".to_string())])?;
    Ok(chat["messages"].items().to_vec())
}

fn reload(app: &mut App) -> Result<()> {
    let Screen::Chat(chat) = &app.screen else { return Ok(()) };
    let tool = chat.tool.clone();
    let messages = fetch(app, &tool)?;
    if let Screen::Chat(chat) = &mut app.screen {
        chat.messages = messages;
    }
    Ok(())
}

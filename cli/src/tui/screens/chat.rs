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

pub const HELP: [(&str, &str); 10] = [
    ("i / enter", "Write a message"),
    ("enter", "Send it (while writing)"),
    ("esc", "Stop writing; again to go home"),
    ("↑ ↓ / j k", "Scroll"),
    ("end / G", "Jump to the newest message"),
    ("home", "Jump to the oldest loaded; again for older ones"),
    ("+", "Put a 👍 on the newest message"),
    ("u", "Undo: unsend your message, or take the 👍 back"),
    ("o", "Open the chat in your browser"),
    ("r", "Reload (it also reloads by itself)"),
];

/// How many messages a chat loads at a time.
pub const PAGE: usize = 60;

pub struct Chat {
    pub tool: Value,
    messages: Vec<Value>,
    /// Whether the server has older messages than the first one here.
    has_more: bool,
    loading_older: bool,
    input: TextInput,
    writing: bool,
    /// Lines scrolled up from the newest message.
    scroll: usize,
    /// Messages that came in while you were scrolled up.
    unseen: usize,
    /// The size last drawn at, to keep your place when messages come in.
    width: usize,
    height: usize,
}

impl Chat {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        let chat = fetch(app, &tool, None)?;
        Ok(Self {
            tool,
            messages: chat["messages"].items().to_vec(),
            has_more: chat["has_more"].truthy(),
            loading_older: false,
            input: TextInput::default(),
            writing: false,
            scroll: 0,
            unseen: 0,
            width: 80,
            height: 20,
        })
    }

    pub fn hints(&self) -> Vec<(&'static str, &'static str)> {
        if self.writing {
            vec![("enter", "send"), ("esc", "stop writing")]
        } else {
            vec![("i", "write"), ("↑↓", "scroll"), ("+", "👍 newest"), ("esc", "home")]
        }
    }

    pub fn refresh(&self) -> Job {
        Box::new(reload)
    }

    /// Takes in the newest messages, keeping older ones already loaded, what
    /// you're writing, and the spot you scrolled to.
    pub fn merge(&mut self, chat: Value) {
        let fresh = chat["messages"].items();
        let Some(first) = fresh.first().map(|message| message["id"].int()) else { return };
        let known: Vec<i64> = self.messages.iter().map(|message| message["id"].int()).collect();
        let arrived = fresh.iter().filter(|message| !known.contains(&message["id"].int())).count();
        let before = self.lines(self.width).len();

        let mut messages: Vec<Value> = self.messages.iter().filter(|message| message["id"].int() < first).cloned().collect();
        if messages.is_empty() {
            self.has_more = chat["has_more"].truthy();
        }
        messages.extend(fresh.iter().cloned());
        self.messages = messages;

        if self.scroll > 0 {
            self.scroll += self.lines(self.width).len().saturating_sub(before);
            self.unseen += arrived;
        }
    }

    fn top(&self) -> usize {
        self.lines(self.width).len().saturating_sub(self.height)
    }

    fn scroll_up(&mut self, lines: usize, fx: &mut Fx) {
        let top = self.top();
        if self.scroll >= top && self.has_more && !self.loading_older {
            self.loading_older = true;
            let (tool, before) = (self.tool.clone(), self.messages.first().map(|message| message["id"].int()));
            fx.job("Loading older messages", move |app| {
                let older = fetch(app, &tool, before)?;
                if let Screen::Chat(chat) = &mut app.screen {
                    let mut messages = older["messages"].items().to_vec();
                    messages.append(&mut chat.messages);
                    chat.messages = messages;
                    chat.has_more = older["has_more"].truthy();
                    chat.loading_older = false;
                }
                Ok(())
            });
        }
        self.scroll = (self.scroll + lines).min(top.max(self.scroll));
    }

    fn scroll_down(&mut self, lines: usize) {
        self.scroll = self.scroll.saturating_sub(lines);
        if self.scroll == 0 {
            self.unseen = 0;
        }
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        if self.writing {
            match key.code {
                KeyCode::Esc => self.writing = false,
                KeyCode::Enter => {
                    if !self.input.is_blank() {
                        let text = self.input.text().trim().to_string();
                        self.input.clear();
                        self.scroll_down(usize::MAX);
                        let tool = self.tool["id"].int();
                        fx.job("Sending", move |app| {
                            let message =
                                app.post(&format!("/tools/{tool}/chat/messages"), json!({ "message": { "body": paragraphs(&text) } }))?;
                            reload(app)?;
                            let id = message["id"].int();
                            app.offer_undo("the message", move |app| {
                                app.delete(&format!("/tools/{tool}/chat/messages/{id}"))?;
                                reload(app)
                            });
                            Ok(())
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
            KeyCode::Up | KeyCode::Char('k') => self.scroll_up(1, fx),
            KeyCode::Down | KeyCode::Char('j') => self.scroll_down(1),
            KeyCode::PageUp => self.scroll_up(self.height.saturating_sub(2).max(1), fx),
            KeyCode::PageDown | KeyCode::Char(' ') => self.scroll_down(self.height.saturating_sub(2).max(1)),
            KeyCode::Home => self.scroll_up(usize::MAX / 2, fx),
            KeyCode::End | KeyCode::Char('G') => self.scroll_down(usize::MAX),
            KeyCode::Char('+') => {
                if let Some(message) = self.messages.last() {
                    let (tool, id) = (self.tool["id"].int(), message["id"].int());
                    let author = message["user"]["name"].opt().unwrap_or_else(|| "someone".into());
                    let path = format!("/tools/{tool}/chat/messages/{id}/reactions");
                    fx.job("Reacting", move |app| {
                        app.post(&path, json!({ "emoji": "👍" }))?;
                        reload(app)?;
                        app.toast(format!("👍 for {author}"), Tone::Success);
                        app.offer_undo("the 👍", move |app| {
                            let emoji: String = url::form_urlencoded::byte_serialize("👍".as_bytes()).collect();
                            app.delete(&format!("{path}/{emoji}"))?;
                            reload(app)
                        });
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

        self.width = usize::from(inner.width.saturating_sub(2));
        self.height = usize::from(inner.height);
        let lines = self.lines(self.width);
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
                let text = match self.unseen {
                    0 => " ↓ newer below · G to jump ".to_string(),
                    1 => " ↓ 1 new message · G to jump ".to_string(),
                    count => format!(" ↓ {count} new messages · G to jump "),
                };
                let note = Span::styled(text, Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD));
                frame.render_widget(Line::from(note).right_aligned(), Rect { y: messages_area.bottom() - 1, height: 1, ..messages_area });
            }
            if start == 0 && lines.len() > height {
                let top = if self.loading_older {
                    " ↑ loading older messages… "
                } else if self.has_more {
                    " ↑ scroll up for older messages "
                } else {
                    " the beginning of this chat 🌱 "
                };
                frame.render_widget(Line::from(Span::styled(top, theme::dim())).centered(), Rect { height: 1, ..messages_area });
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

/// The newest page of messages, or the page before message `before`.
fn fetch(app: &mut App, tool: &Value, before: Option<i64>) -> Result<Value> {
    let mut params = vec![("limit", PAGE.to_string())];
    params.extend(before.map(|id| ("before", id.to_string())));
    app.get(&format!("/tools/{}/chat", tool["id"].s()), &params)
}

fn reload(app: &mut App) -> Result<()> {
    let Screen::Chat(chat) = &app.screen else { return Ok(()) };
    let tool = chat.tool.clone();
    let fresh = fetch(app, &tool, None)?;
    if let Screen::Chat(chat) = &mut app.screen {
        chat.merge(fresh);
    }
    Ok(())
}

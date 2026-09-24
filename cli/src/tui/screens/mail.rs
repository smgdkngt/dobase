//! Mail, to read: conversations per folder, each opened as a whole thread.

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph};
use serde_json::Value;

use super::move_selection;
use crate::command::Result;
use crate::tui::app::{App, Fx, Job};
use crate::tui::popups::{self, Detail, Popup};
use crate::tui::screens::Screen;
use crate::tui::theme;
use crate::tui::widgets::{ago, panel, truncate};
use crate::value::Json;

pub const HINTS: [(&str, &str); 5] = [("↑↓", "choose"), ("enter", "read"), ("f", "folder"), ("o", "browser"), ("esc", "home")];

pub const HELP: [(&str, &str); 6] = [
    ("↑ ↓ / j k", "Choose a conversation"),
    ("enter", "Read it (this doesn't mark it read)"),
    ("f", "Next folder: inbox, starred, sent, archive, drafts"),
    ("o", "Open it in your browser to reply"),
    ("r", "Reload"),
    ("esc", "Back home"),
];

const FOLDERS: [&str; 5] = ["inbox", "starred", "sent", "archive", "drafts"];

pub struct Mail {
    pub tool: Value,
    mailbox: Value,
    folder: usize,
    selected: usize,
}

impl Mail {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        Self::load_folder(app, tool, 0)
    }

    fn load_folder(app: &mut App, tool: Value, folder: usize) -> Result<Self> {
        let mailbox = app.get(&format!("/tools/{}/mails", tool["id"].s()), &[("folder", FOLDERS[folder].to_string())])?;
        Ok(Self { tool, mailbox, folder, selected: 0 })
    }

    fn conversations(&self) -> &[Value] {
        self.mailbox["conversations"].items()
    }

    pub fn refresh(&self) -> Job {
        let (tool, folder, selected) = (self.tool.clone(), self.folder, self.selected);
        Box::new(move |app: &mut App| {
            let mut fresh = Mail::load_folder(app, tool, folder)?;
            fresh.selected = selected;
            app.screen = Screen::Mail(fresh);
            Ok(())
        })
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        let tool = self.tool["id"].int();
        match key.code {
            KeyCode::Char('f') => {
                let (tool, folder) = (self.tool.clone(), (self.folder + 1) % FOLDERS.len());
                fx.job(format!("Opening {}", FOLDERS[folder]), move |app| {
                    app.screen = Screen::Mail(Mail::load_folder(app, tool, folder)?);
                    Ok(())
                });
            }
            KeyCode::Enter => {
                if let Some(conversation) = self.conversations().get(self.selected) {
                    let id = conversation["id"].int();
                    fx.job("Opening the conversation", move |app| {
                        app.popup = Some(Popup::Detail(conversation_detail(app, tool, id)?));
                        Ok(())
                    });
                }
            }
            KeyCode::Char('o') => {
                fx.open_url = Some(match self.conversations().get(self.selected) {
                    Some(conversation) => format!("/tools/{tool}/mails/{}", conversation["id"].s()),
                    None => format!("/tools/{tool}/mails"),
                })
            }
            _ => {
                let count = self.conversations().len();
                return move_selection(&mut self.selected, count, key);
            }
        }
        true
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        let tabs: Vec<Span> = FOLDERS
            .iter()
            .enumerate()
            .flat_map(|(index, folder)| {
                let style = if index == self.folder {
                    Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
                } else {
                    theme::dim()
                };
                [Span::styled(folder.to_string(), style), Span::raw("  ")]
            })
            .collect();
        let (name, address) = (self.tool["name"].s(), self.mailbox["account"]["email_address"].s());
        let title = if address.is_empty() || name.eq_ignore_ascii_case(&address) {
            format!("{} {name}", theme::tool_icon("mail"))
        } else {
            format!("{} {name} · {address}", theme::tool_icon("mail"))
        };
        let block = panel(title, true).title_bottom(Line::from(tabs).right_aligned());

        let conversations = self.conversations();
        if conversations.is_empty() {
            let message = if self.folder == 0 { "Inbox zero. Go outside 🌳" } else { "Nothing in here." };
            frame.render_widget(Paragraph::new(message).style(theme::dim()).block(block), area);
            return;
        }
        let width = usize::from(area.width.saturating_sub(4));
        let items: Vec<ListItem> = conversations
            .iter()
            .map(|conversation| {
                let unread = !conversation["read"].truthy();
                let from = if conversation["draft"].truthy() { "Draft".to_string() } else { conversation["from"].s() };
                let mut badges = String::new();
                if conversation["starred"].truthy() {
                    badges.push_str(" ⭐");
                }
                if conversation["has_attachments"].truthy() {
                    badges.push_str(" 📎");
                }
                if conversation["messages_count"].int() > 1 {
                    badges.push_str(&format!(" ({})", conversation["messages_count"].int()));
                }
                let style = if unread { theme::bold() } else { Style::new() };
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(if unread { "● " } else { "  " }, Style::new().fg(theme::accent())),
                        Span::styled(truncate(&from, width / 2), style),
                        Span::styled(format!("  {}{badges}", ago(&conversation["sent_at"])), theme::dim()),
                    ]),
                    Line::from(Span::styled(format!("  {}", truncate(&conversation["subject"].s(), width.saturating_sub(2))), style)),
                ])
            })
            .collect();
        self.selected = self.selected.min(items.len() - 1);
        let list = List::new(items).block(block).highlight_style(theme::selected());
        frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(Some(self.selected)));
    }
}

pub fn conversation_detail(app: &mut App, tool: i64, id: i64) -> Result<Detail> {
    let conversation = app.get(&format!("/tools/{tool}/mails/{id}"), &[])?;
    let mut lines = Vec::new();
    for message in conversation["messages"].items() {
        let from = match message["from_name"].opt().filter(|name| !name.is_empty()) {
            Some(name) => format!("{name} <{}>", message["from_address"].s()),
            None => message["from_address"].s(),
        };
        popups::heading(&mut lines, from);
        let to = message["to"].items().iter().map(Json::s).collect::<Vec<_>>().join(", ");
        popups::field(&mut lines, "To", Some(to));
        popups::field(&mut lines, "Sent", Some(ago(&message["sent_at"])));
        lines.push(Line::raw(""));
        popups::text(&mut lines, &message["body"].s(), 0);
        let attachments = message["attachments"].items();
        if !attachments.is_empty() {
            let names = attachments.iter().map(|attachment| attachment["filename"].s()).collect::<Vec<_>>().join(", ");
            lines.push(Line::from(Span::styled(format!("📎 {names}"), theme::dim())));
        }
    }
    Ok(Detail {
        title: truncate(&conversation["subject"].s(), 80),
        lines,
        scroll: 0,
        url: Some(format!("/tools/{tool}/mails/{id}")),
        comment: None,
    })
}

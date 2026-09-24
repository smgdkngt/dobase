//! Docs: the documents on the left, the one you open on the right.

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph, Wrap};
use serde_json::Value;

use super::move_selection;
use crate::command::Result;
use crate::tui::app::{App, Fx, Job};
use crate::tui::screens::Screen;
use crate::tui::theme;
use crate::tui::widgets::{ago, panel, truncate};
use crate::value::Json;

pub const HINTS: [(&str, &str); 5] = [("↑↓", "choose"), ("enter", "read"), ("tab", "switch pane"), ("o", "browser"), ("esc", "home")];

pub const HELP: [(&str, &str); 6] = [
    ("↑ ↓ / j k", "Choose a document, or scroll it"),
    ("enter", "Read the document"),
    ("tab", "Switch between the list and the document"),
    ("o", "Open the document in your browser to edit it"),
    ("r", "Reload"),
    ("esc", "Back to the list, then home"),
];

pub struct Docs {
    pub tool: Value,
    documents: Vec<Value>,
    selected: usize,
    open: Option<Value>,
    reading: bool,
    scroll: u16,
}

impl Docs {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        let docs = app.get(&format!("/tools/{}/docs", tool["id"].s()), &[])?;
        Ok(Self { tool, documents: docs["documents"].items().to_vec(), selected: 0, open: None, reading: false, scroll: 0 })
    }

    /// Shows `document` on the right, selecting it in the list.
    pub fn show(&mut self, document: Value) {
        if let Some(position) = self.documents.iter().position(|other| other["id"] == document["id"]) {
            self.selected = position;
        }
        self.open = Some(document);
        self.reading = true;
        self.scroll = 0;
    }

    pub fn refresh(&self) -> Job {
        let (tool, selected, open) = (self.tool.clone(), self.selected, self.open.as_ref().map(|document| document["id"].int()));
        Box::new(move |app: &mut App| {
            let mut fresh = Docs::load(app, tool.clone())?;
            fresh.selected = selected.min(fresh.documents.len().saturating_sub(1));
            if let Some(id) = open {
                fresh.open = Some(app.get(&format!("/tools/{}/docs/documents/{id}", tool["id"].s()), &[])?);
            }
            if let Screen::Docs(docs) = &mut app.screen {
                fresh.reading = docs.reading;
                fresh.scroll = docs.scroll;
                *docs = fresh;
            }
            Ok(())
        })
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        match key.code {
            KeyCode::Tab | KeyCode::BackTab => self.reading = !self.reading && self.open.is_some(),
            KeyCode::Esc if self.reading => self.reading = false,
            KeyCode::Enter | KeyCode::Right | KeyCode::Char('l') if !self.reading => {
                let Some(document) = self.documents.get(self.selected) else { return true };
                let (tool, id) = (self.tool["id"].s(), document["id"].s());
                fx.job("Opening the document", move |app| {
                    let document = app.get(&format!("/tools/{tool}/docs/documents/{id}"), &[])?;
                    if let Screen::Docs(docs) = &mut app.screen {
                        docs.show(document);
                    }
                    Ok(())
                });
            }
            KeyCode::Left | KeyCode::Char('h') if self.reading => self.reading = false,
            KeyCode::Down | KeyCode::Char('j') if self.reading => self.scroll = self.scroll.saturating_add(1),
            KeyCode::Up | KeyCode::Char('k') if self.reading => self.scroll = self.scroll.saturating_sub(1),
            KeyCode::PageDown | KeyCode::Char(' ') if self.reading => self.scroll = self.scroll.saturating_add(15),
            KeyCode::PageUp if self.reading => self.scroll = self.scroll.saturating_sub(15),
            KeyCode::Char('o') => {
                let document = if self.reading { self.open.as_ref() } else { self.documents.get(self.selected) };
                match document {
                    Some(document) => fx.open_url = Some(format!("/tools/{}/docs/documents/{}", self.tool["id"].s(), document["id"].s())),
                    None => return false,
                }
            }
            _ if !self.reading => return move_selection(&mut self.selected, self.documents.len(), key),
            _ => return false,
        }
        true
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        let [list_area, page_area] = Layout::horizontal([Constraint::Percentage(32), Constraint::Percentage(68)]).spacing(1).areas(area);

        let width = usize::from(list_area.width.saturating_sub(4));
        let items: Vec<ListItem> = self
            .documents
            .iter()
            .map(|document| {
                let editing =
                    if document["locked"].truthy() { format!(" ✎ {}", document["locked_by"]["name"].s()) } else { String::new() };
                ListItem::new(vec![
                    Line::from(Span::styled(truncate(&document["title"].s(), width), theme::bold())),
                    Line::from(Span::styled(format!("{}{editing}", ago(&document["updated_at"])), theme::dim())),
                ])
            })
            .collect();
        let block = panel(format!("{} {}", theme::tool_icon("docs"), self.tool["name"].s()), !self.reading);
        if items.is_empty() {
            frame.render_widget(Paragraph::new("No documents yet.").style(theme::dim()).block(block), list_area);
        } else {
            let list = List::new(items).block(block).highlight_style(theme::selected());
            frame.render_stateful_widget(list, list_area, &mut ListState::default().with_selected(Some(self.selected)));
        }

        match &self.open {
            None => {
                let hint = Paragraph::new(vec![
                    Line::raw(""),
                    Line::from(Span::styled("Press enter to read a document 📖", theme::dim())).centered(),
                ])
                .block(panel("📖", false));
                frame.render_widget(hint, page_area);
            }
            Some(document) => {
                let mut lines = vec![
                    Line::from(Span::styled(
                        format!("Edited {} by {}", ago(&document["updated_at"]), document["updated_by"]["name"].s()),
                        theme::dim(),
                    )),
                    Line::raw(""),
                ];
                let content = document["content"].s();
                if content.trim().is_empty() {
                    lines.push(Line::from(Span::styled("(empty)", theme::dim())));
                }
                lines.extend(crate::command::clean(&content).lines().map(|line| Line::raw(line.to_string())));
                let paragraph = Paragraph::new(lines)
                    .wrap(Wrap { trim: false })
                    .block(panel(document["title"].s(), self.reading))
                    .scroll((self.scroll, 0));
                frame.render_widget(paragraph, page_area);
            }
        }
    }
}

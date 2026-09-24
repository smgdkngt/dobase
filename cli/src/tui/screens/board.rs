//! A board: its columns side by side, cards you can open, add and move.

use std::rc::Rc;

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Paragraph};
use serde_json::{Value, json};

use crate::command::{Result, bytes, today};
use crate::tui::app::{App, Fx, Job, Tone};
use crate::tui::popups::{self, CommentOn, Detail, Popup};
use crate::tui::theme;
use crate::tui::widgets::{ago, panel, truncate, wrap};
use crate::value::Json;

pub const HINTS: [(&str, &str); 6] =
    [("←→↑↓", "move"), ("enter", "open"), ("c", "new card"), ("H L", "move card"), ("i", "assign me"), ("esc", "home")];

pub const HELP: [(&str, &str); 11] = [
    ("← → / h l", "Previous or next column"),
    ("↑ ↓ / j k", "Previous or next card"),
    ("enter", "Open the card: description and comments"),
    ("c", "New card at the bottom of this column"),
    ("H L", "Move the card to the previous or next column"),
    ("K J", "Move the card up or down its column"),
    ("i", "Assign the card to yourself, or unassign"),
    ("a", "Archive the card"),
    ("o", "Open the card in your browser"),
    ("r", "Reload the board"),
    ("esc", "Back home"),
];

const COLUMN_WIDTH: u16 = 30;

pub struct Board {
    pub tool: Value,
    columns: Vec<Value>,
    column: usize,
    /// The selected card in each column.
    cards: Vec<usize>,
}

impl Board {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        let board = app.get(&format!("/tools/{}/board", tool["id"].s()), &[])?;
        let columns = board["columns"].items().to_vec();
        let cards = vec![0; columns.len()];
        Ok(Self { tool, columns, column: 0, cards })
    }

    fn tool_id(&self) -> i64 {
        self.tool["id"].int()
    }

    fn card(&self) -> Option<&Value> {
        self.columns.get(self.column)?["cards"].items().get(*self.cards.get(self.column)?)
    }

    pub fn refresh(&self) -> Job {
        let tool = self.tool.clone();
        let (column, selected) = (self.column, self.card().map(|card| card["id"].int()));
        Box::new(move |app: &mut App| {
            let fresh = Board::load(app, tool)?;
            if let crate::tui::screens::Screen::Board(board) = &mut app.screen {
                let old_cards = std::mem::take(&mut board.cards);
                *board = Board { cards: old_cards, ..fresh };
                board.column = column.min(board.columns.len().saturating_sub(1));
                board.cards.resize(board.columns.len(), 0);
                if let Some(id) = selected {
                    board.select_card(id);
                }
                board.clamp();
            }
            Ok(())
        })
    }

    /// Selects the card with this id, wherever it is.
    pub fn select(&mut self, id: i64) {
        self.select_card(id);
    }

    fn select_card(&mut self, id: i64) {
        for (column_index, column) in self.columns.iter().enumerate() {
            if let Some(position) = column["cards"].items().iter().position(|card| card["id"].int() == id) {
                self.column = column_index;
                self.cards[column_index] = position;
            }
        }
    }

    fn clamp(&mut self) {
        for (index, column) in self.columns.iter().enumerate() {
            self.cards[index] = self.cards[index].min(column["cards"].items().len().saturating_sub(1));
        }
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        let count = self.columns.get(self.column).map(|column| column["cards"].items().len()).unwrap_or(0);
        match key.code {
            KeyCode::Left | KeyCode::Char('h') => self.column = self.column.saturating_sub(1),
            KeyCode::Right | KeyCode::Char('l') => self.column = (self.column + 1).min(self.columns.len().saturating_sub(1)),
            KeyCode::Down | KeyCode::Char('j') => self.cards[self.column] = (self.cards[self.column] + 1).min(count.saturating_sub(1)),
            KeyCode::Up | KeyCode::Char('k') => self.cards[self.column] = self.cards[self.column].saturating_sub(1),
            KeyCode::Enter => {
                if let Some(card) = self.card() {
                    let (tool, id) = (self.tool_id(), card["id"].int());
                    fx.job("Opening the card", move |app| {
                        app.popup = Some(Popup::Detail(card_detail(app, tool, id)?));
                        Ok(())
                    });
                }
            }
            KeyCode::Char('c') => {
                let Some(column) = self.columns.get(self.column) else { return true };
                let (column_id, name) = (column["id"].s(), column["name"].s());
                fx.popup = Some(Popup::input(&format!("New card in {name}"), "What needs doing?", "Adding the card", move |app, title| {
                    let card = app.post(&format!("/columns/{column_id}/cards"), json!({ "card": { "title": title } }))?;
                    reload(app, Some(card["id"].int()))?;
                    app.toast(format!("Added “{}” 📝", card["title"].s()), Tone::Success);
                    Ok(())
                }));
            }
            KeyCode::Char('H') | KeyCode::Char('L') => self.move_across(key.code == KeyCode::Char('L'), fx),
            KeyCode::Char('K') | KeyCode::Char('J') => self.move_within(key.code == KeyCode::Char('J'), fx),
            KeyCode::Char('i') => {
                if let Some(card) = self.card() {
                    let (tool, id, assignee) = (self.tool_id(), card["id"].int(), card["assignee"]["id"].clone());
                    fx.job("Assigning", move |app| {
                        let mine = assignee == app.me["id"];
                        let value = if mine { Value::Null } else { app.me["id"].clone() };
                        app.patch(&format!("/tools/{tool}/board/cards/{id}"), json!({ "card": { "assigned_user_id": value } }))?;
                        reload(app, Some(id))?;
                        app.toast(if mine { "Unassigned" } else { "It's yours now 👍" }, Tone::Success);
                        Ok(())
                    });
                }
            }
            KeyCode::Char('a') => {
                if let Some(card) = self.card() {
                    let (tool, id, title) = (self.tool_id(), card["id"].int(), card["title"].s());
                    fx.popup = Some(Popup::confirm(
                        format!("Archive “{title}”? You can bring it back in the browser."),
                        "Archiving",
                        move |app| {
                            app.post(&format!("/tools/{tool}/board/cards/{id}/archive"), json!({}))?;
                            reload(app, None)?;
                            app.toast("Archived 📦", Tone::Success);
                            Ok(())
                        },
                    ));
                }
            }
            KeyCode::Char('o') => match self.card() {
                Some(card) => fx.open_url = Some(format!("/tools/{}/board?card={}", self.tool_id(), card["id"].s())),
                None => return false,
            },
            _ => return false,
        }
        true
    }

    /// Moves the selected card to the bottom of the next or previous column, right away on screen.
    fn move_across(&mut self, forward: bool, fx: &mut Fx) {
        let target = if forward { self.column + 1 } else { self.column.wrapping_sub(1) };
        if target >= self.columns.len() || self.card().is_none() {
            return;
        }
        let card = self.take_card(self.column, self.cards[self.column]);
        let (tool, id, column_id, column_name) =
            (self.tool_id(), card["id"].int(), self.columns[target]["id"].clone(), self.columns[target]["name"].s());
        push_card(&mut self.columns[target], card);
        self.column = target;
        self.cards[target] = self.columns[target]["cards"].items().len() - 1;
        if theme::is_done_column(&column_name) {
            fx.confetti = true;
        }
        fx.job(format!("Moving to {column_name}"), move |app| {
            app.patch(&format!("/tools/{tool}/board/cards/{id}/position"), json!({ "column_id": column_id }))?;
            reload(app, Some(id))
        });
    }

    fn move_within(&mut self, down: bool, fx: &mut Fx) {
        let (column, index) = (self.column, self.cards[self.column]);
        let count = self.columns[column]["cards"].items().len();
        let target = if down { index + 1 } else { index.wrapping_sub(1) };
        if target >= count {
            return;
        }
        if let Some(cards) = self.columns[column]["cards"].as_array_mut() {
            cards.swap(index, target);
        }
        self.cards[column] = target;
        let (tool, id) = (self.tool_id(), self.columns[column]["cards"][target]["id"].int());
        fx.job("Moving", move |app| {
            app.patch(&format!("/tools/{tool}/board/cards/{id}/position"), json!({ "position": target }))?;
            reload(app, Some(id))
        });
    }

    fn take_card(&mut self, column: usize, index: usize) -> Value {
        let card = self.columns[column]["cards"].as_array_mut().map(|cards| cards.remove(index)).unwrap_or(Value::Null);
        self.cards[column] = self.cards[column].min(self.columns[column]["cards"].items().len().saturating_sub(1));
        card
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        if self.columns.is_empty() {
            frame.render_widget(Paragraph::new("This board has no columns yet.").style(theme::dim()).block(panel("Board", true)), area);
            return;
        }
        let fits = usize::from((area.width / COLUMN_WIDTH).max(1));
        let first = self.column.saturating_sub(fits - 1).min(self.columns.len().saturating_sub(fits));
        let shown: Vec<usize> = (first..self.columns.len()).take(fits).collect();
        let areas = Layout::horizontal(shown.iter().map(|_| Constraint::Fill(1))).spacing(1).split(area);

        for (slot, &index) in shown.iter().enumerate() {
            self.draw_column(frame, areas[slot], index);
        }
        if first > 0 {
            frame.render_widget(Span::styled("◀", Style::new().fg(theme::accent())), Rect { width: 1, height: 1, ..area });
        }
        if first + shown.len() < self.columns.len() {
            frame.render_widget(
                Span::styled("▶", Style::new().fg(theme::accent())),
                Rect { x: area.right() - 1, width: 1, height: 1, ..area },
            );
        }
    }

    fn draw_column(&self, frame: &mut Frame, area: Rect, index: usize) {
        let column = &self.columns[index];
        let cards = column["cards"].items();
        let focused = index == self.column;
        let title = format!("{} {}", column["name"].s(), cards.len());
        let block = panel(title, focused);
        let inner = block.inner(area);
        frame.render_widget(block, area);

        if cards.is_empty() {
            let hint = if focused { "Nothing here. Press c to add a card." } else { "Nothing here." };
            frame.render_widget(Paragraph::new(hint).style(theme::dim()).wrap(ratatui::widgets::Wrap { trim: true }), inner);
            return;
        }

        let width = usize::from(inner.width.saturating_sub(2));
        let heights: Vec<u16> = cards.iter().map(|card| card_lines(card, width).len() as u16 + 2).collect();
        let selected = self.cards[index];
        // Scroll so the selected card is fully in view.
        let mut first = 0;
        while first < selected && heights[first..=selected].iter().sum::<u16>() > inner.height {
            first += 1;
        }

        let mut y = inner.y;
        for (position, card) in cards.iter().enumerate().skip(first) {
            let height = heights[position];
            if y >= inner.bottom() {
                break;
            }
            let room = inner.bottom() - y;
            let card_area = Rect { x: inner.x, y, width: inner.width, height: height.min(room) };
            let chosen = focused && position == selected;
            let color = theme::card_color(&card["color"].s()).unwrap_or(theme::muted());
            let block = Block::new()
                .borders(Borders::ALL)
                .border_type(if chosen { BorderType::Thick } else { BorderType::Rounded })
                .border_style(if chosen { Style::new().fg(theme::accent()) } else { Style::new().fg(color) });
            let lines = card_lines(card, width);
            let content = Paragraph::new(lines).style(if chosen { Style::new().add_modifier(Modifier::BOLD) } else { Style::new() });
            frame.render_widget(content.block(block), card_area);
            y += height;
        }
        if first > 0 {
            frame.render_widget(
                Span::styled(format!("↑ {first} more"), theme::dim()),
                Rect { x: area.x + 2, y: area.y, width: 12, height: 1 },
            );
        }
    }
}

fn push_card(column: &mut Value, card: Value) {
    if let Some(cards) = column["cards"].as_array_mut() {
        cards.push(card);
    }
}

/// Reloads the board on screen, selecting `card` when given.
fn reload(app: &mut App, card: Option<i64>) -> Result<()> {
    let crate::tui::screens::Screen::Board(board) = &app.screen else { return Ok(()) };
    let (tool, column, cards) = (board.tool.clone(), board.column, board.cards.clone());
    let mut fresh = Board::load(app, tool)?;
    fresh.cards = cards;
    fresh.cards.resize(fresh.columns.len(), 0);
    fresh.column = column.min(fresh.columns.len().saturating_sub(1));
    if let Some(id) = card {
        fresh.select_card(id);
    }
    fresh.clamp();
    app.screen = crate::tui::screens::Screen::Board(fresh);
    Ok(())
}

/// The lines inside a card: its title, then due date, assignee and counts.
fn card_lines(card: &Value, width: usize) -> Vec<Line<'static>> {
    let mut lines: Vec<Line<'static>> = wrap(&card["title"].s(), width).into_iter().take(3).map(Line::from).collect();

    let mut meta = Vec::new();
    if let Some(due) = card["due_date"].opt() {
        let overdue = due < today().to_string();
        meta.push(Span::styled(format!("📅 {} ", short_date(&due)), if overdue { Style::new().fg(theme::danger()) } else { theme::dim() }));
    }
    if let Some(name) = card["assignee"]["name"].opt() {
        let first = name.split_whitespace().next().unwrap_or("").to_string();
        meta.push(Span::styled(format!("@{first} "), Style::new().fg(theme::person_color(&name))));
    }
    if card["comments_count"].int() > 0 {
        meta.push(Span::styled(format!("💬{} ", card["comments_count"].int()), theme::dim()));
    }
    if card["attachments_count"].int() > 0 {
        meta.push(Span::styled(format!("📎{} ", card["attachments_count"].int()), theme::dim()));
    }
    if !meta.is_empty() {
        lines.push(Line::from(meta));
    }
    lines.iter_mut().for_each(|line| *line = Line::from(truncate_line(line, width)));
    lines
}

fn truncate_line(line: &Line<'static>, width: usize) -> Vec<Span<'static>> {
    if line.width() <= width {
        return line.spans.clone();
    }
    let text: String = line.spans.iter().map(|span| span.content.to_string()).collect();
    vec![Span::styled(truncate(&text, width), line.spans.first().map(|span| span.style).unwrap_or_default())]
}

/// "Oct 1" from "2026-10-01".
pub fn short_date(date: &str) -> String {
    date.parse::<jiff::civil::Date>().map(|date| date.strftime("%b %-d").to_string()).unwrap_or_else(|_| date.to_string())
}

/// The popup for a card: its details, description, comments and files.
pub fn card_detail(app: &mut App, tool: i64, id: i64) -> Result<Detail> {
    let card = app.get(&format!("/tools/{tool}/board/cards/{id}"), &[])?;
    let mut lines = Vec::new();
    popups::field(&mut lines, "Column", card["column"]["name"].opt());
    popups::field(&mut lines, "Assignee", card["assignee"]["name"].opt());
    popups::field(&mut lines, "Due", card["due_date"].opt().map(|due| short_date(&due)));
    popups::field(&mut lines, "Color", card["color"].opt());
    popups::field(&mut lines, "Created", Some(ago(&card["created_at"])).map(|at| format!("{at} by {}", card["creator"]["name"].s())));

    let description = card["description"].s();
    if !description.trim().is_empty() {
        popups::heading(&mut lines, "Description");
        popups::text(&mut lines, &description, 0);
    }
    popups::comments(&mut lines, &card);

    let attachments = card["attachments"].items();
    if !attachments.is_empty() {
        popups::heading(&mut lines, format!("📎 Attachments ({})", attachments.len()));
        for attachment in attachments {
            lines.push(Line::raw(format!("  {}  {}", attachment["filename"].s(), bytes(&attachment["file_size"]))));
        }
    }

    Ok(Detail {
        title: card["title"].s(),
        lines,
        scroll: 0,
        url: card["url"].opt(),
        comment: Some(CommentOn {
            path: format!("/tools/{tool}/board/cards/{id}/comments"),
            reload: Rc::new(move |app| card_detail(app, tool, id)),
        }),
    })
}

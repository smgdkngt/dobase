//! A todos tool: every list with its todos, ticked off with the spacebar.

use std::rc::Rc;

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph};
use serde_json::{Value, json};

use super::board::short_date;
use super::move_selection;
use crate::command::{Result, bytes, today};
use crate::tui::app::{App, Fx, Job, Tone};
use crate::tui::popups::{self, CommentOn, Detail, Popup};
use crate::tui::screens::Screen;
use crate::tui::theme;
use crate::tui::widgets::{ago, due_date, panel, truncate};
use crate::value::Json;

pub const HINTS: [(&str, &str); 6] =
    [("↑↓", "choose"), ("space", "done"), ("enter", "open"), ("c", "new"), ("e d", "rename, due"), ("esc", "home")];

pub const HELP: [(&str, &str); 12] = [
    ("↑ ↓ / j k", "Choose a todo"),
    ("space / x", "Tick it off, or reopen it"),
    ("enter", "Open it: description and comments"),
    ("c", "New todo at the bottom of this list"),
    ("N", "New list"),
    ("e", "Rename it"),
    ("d", "Set its due date: fri, +3, tomorrow, 2026-10-01 or none"),
    ("i", "Assign it to yourself, or unassign"),
    ("o", "Open it in your browser"),
    ("u", "Undo the last change"),
    ("r", "Reload"),
    ("esc", "Back home"),
];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Row {
    List(usize),
    Item(usize, usize),
}

pub struct Todos {
    pub tool: Value,
    lists: Vec<Value>,
    rows: Vec<Row>,
    selected: usize,
}

impl Todos {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        let todo = app.get(&format!("/tools/{}/todo", tool["id"].s()), &[])?;
        let lists = todo["lists"].items().to_vec();
        let mut screen = Self { tool, lists, rows: Vec::new(), selected: 0 };
        screen.index();
        screen.selected = screen.rows.iter().position(|row| matches!(row, Row::Item(..))).unwrap_or(0);
        Ok(screen)
    }

    fn index(&mut self) {
        self.rows.clear();
        for (list, value) in self.lists.iter().enumerate() {
            self.rows.push(Row::List(list));
            self.rows.extend((0..value["items"].items().len()).map(|item| Row::Item(list, item)));
        }
    }

    fn tool_id(&self) -> i64 {
        self.tool["id"].int()
    }

    fn item(&self) -> Option<&Value> {
        match self.rows.get(self.selected)? {
            Row::Item(list, item) => self.lists[*list]["items"].items().get(*item),
            Row::List(_) => None,
        }
    }

    fn list(&self) -> Option<&Value> {
        match self.rows.get(self.selected)? {
            Row::Item(list, _) | Row::List(list) => self.lists.get(*list),
        }
    }

    pub fn select(&mut self, id: i64) {
        self.select_item(id);
    }

    fn select_item(&mut self, id: i64) {
        if let Some(position) = self.rows.iter().position(|row| match row {
            Row::Item(list, item) => self.lists[*list]["items"][*item]["id"].int() == id,
            Row::List(_) => false,
        }) {
            self.selected = position;
        }
    }

    pub fn refresh(&self) -> Job {
        Box::new(|app: &mut App| reload(app, None))
    }

    /// Takes in fresh lists, keeping the selection on the same todo (or `select`).
    pub fn replace(&mut self, lists: Vec<Value>, select: Option<i64>) {
        let selected = select.or_else(|| self.item().map(|item| item["id"].int()));
        self.lists = lists;
        self.index();
        self.selected = self.selected.min(self.rows.len().saturating_sub(1));
        if let Some(id) = selected {
            self.select_item(id);
        }
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        match key.code {
            KeyCode::Char(' ') | KeyCode::Char('x') => self.toggle(fx),
            KeyCode::Enter => {
                if let Some(item) = self.item() {
                    let (tool, id) = (self.tool_id(), item["id"].int());
                    fx.job("Opening the todo", move |app| {
                        app.popup = Some(Popup::Detail(todo_detail(app, tool, id)?));
                        Ok(())
                    });
                }
            }
            KeyCode::Char('c') => {
                let Some(list) = self.list() else { return true };
                let (list_id, name) = (list["id"].s(), list["title"].s());
                fx.popup = Some(Popup::input(&format!("New todo in {name}"), "What needs doing?", "Adding the todo", move |app, title| {
                    let item = app.post(&format!("/todo_lists/{list_id}/items"), json!({ "item": { "title": title } }))?;
                    reload(app, Some(item["id"].int()))?;
                    app.toast(format!("Added “{}” 📝", item["title"].s()), Tone::Success);
                    Ok(())
                }));
            }
            KeyCode::Char('N') => {
                let tool = self.tool_id();
                fx.popup = Some(Popup::input("New list", "What's the list called?", "Adding the list", move |app, title| {
                    app.post(&format!("/tools/{tool}/todo/lists"), json!({ "title": title }))?;
                    reload(app, None)?;
                    app.toast(format!("Made the list “{title}”"), Tone::Success);
                    Ok(())
                }));
            }
            KeyCode::Char('i') => {
                if let Some(item) = self.item() {
                    let (tool, id, assignee) = (self.tool_id(), item["id"].int(), item["assignee"]["id"].clone());
                    fx.job("Assigning", move |app| {
                        let mine = assignee == app.me["id"];
                        let value = if mine { Value::Null } else { app.me["id"].clone() };
                        update_item(app, tool, id, json!({ "assigned_user_id": value }))?;
                        app.toast(if mine { "Unassigned" } else { "It's yours now 👍" }, Tone::Success);
                        app.offer_undo("the assignment", move |app| update_item(app, tool, id, json!({ "assigned_user_id": assignee })));
                        Ok(())
                    });
                }
            }
            KeyCode::Char('e') => {
                if let Some(item) = self.item() {
                    let (tool, id, old) = (self.tool_id(), item["id"].int(), item["title"].s());
                    fx.popup = Some(
                        Popup::input("Rename the todo", "A new title", "Renaming", move |app, title| {
                            update_item(app, tool, id, json!({ "title": title }))?;
                            app.offer_undo("the rename", move |app| update_item(app, tool, id, json!({ "title": old })));
                            Ok(())
                        })
                        .prefilled(&item["title"].s()),
                    );
                }
            }
            KeyCode::Char('d') => {
                if let Some(item) = self.item() {
                    let (tool, id, old) = (self.tool_id(), item["id"].int(), item["due_date"].clone());
                    fx.popup = Some(
                        Popup::input("Due date", "fri, +3, tomorrow, 2026-10-01 or none", "Setting the due date", move |app, text| {
                            let due = due_date(&text).map_err(crate::command::Error::usage)?;
                            update_item(app, tool, id, json!({ "due_date": due.map(|date| date.to_string()) }))?;
                            app.toast(
                                due.map_or("No due date".to_string(), |date| format!("Due {}", short_date(&date.to_string()))),
                                Tone::Success,
                            );
                            app.offer_undo("the due date", move |app| update_item(app, tool, id, json!({ "due_date": old })));
                            Ok(())
                        })
                        .prefilled(&item["due_date"].s()),
                    );
                }
            }
            KeyCode::Char('o') => match self.item() {
                Some(item) => fx.open_url = Some(format!("/tools/{}/todo?item={}", self.tool_id(), item["id"].s())),
                None => return false,
            },
            _ => return move_selection(&mut self.selected, self.rows.len(), key),
        }
        true
    }

    /// Ticks the selected todo off (or reopens it) right away on screen.
    fn toggle(&mut self, fx: &mut Fx) {
        let Some(Row::Item(list, index)) = self.rows.get(self.selected).copied() else { return };
        let tool = self.tool_id();
        let item = &mut self.lists[list]["items"][index];
        let done = !item["completed"].truthy();
        item["completed"] = json!(done);
        let id = item["id"].int();
        if done {
            fx.confetti = true;
        }
        fx.job(if done { "Ticking it off" } else { "Reopening" }, move |app| {
            let path = format!("/tools/{tool}/todo/items/{id}/completion");
            let item = if done { app.post(&path, json!({}))? } else { app.delete(&path)? };
            reload(app, Some(id))?;
            if done && item["recurrence_rule"].truthy() {
                // Its next one is already on the list, so there's nothing simple to undo.
                app.toast(format!("Done! It's back {} 🔁", item["recurrence_rule"].s()), Tone::Success);
            } else {
                app.offer_undo(if done { "the tick" } else { "the reopening" }, move |app| {
                    if done {
                        app.delete(&path)?
                    } else {
                        app.post(&path, json!({}))?
                    };
                    reload(app, Some(id))
                });
            }
            Ok(())
        });
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        let block = panel(format!("{} {}", theme::tool_icon("todos"), self.tool["name"].s()), true);
        if self.lists.is_empty() {
            frame.render_widget(Paragraph::new("No lists yet. Press N to make one.").style(theme::dim()).block(block), area);
            return;
        }
        let width = usize::from(area.width.saturating_sub(8));
        let items: Vec<ListItem> = self
            .rows
            .iter()
            .map(|row| match *row {
                Row::List(list) => {
                    let items = self.lists[list]["items"].items();
                    let open = items.iter().filter(|item| !item["completed"].truthy()).count();
                    let spacer = if list == 0 { Line::raw("") } else { Line::raw(" ") };
                    ListItem::new(vec![
                        spacer,
                        Line::from(vec![
                            Span::styled(self.lists[list]["title"].s(), Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD)),
                            Span::styled(format!("  {open} open"), theme::dim()),
                        ]),
                    ])
                }
                Row::Item(list, item) => item_line(&self.lists[list]["items"][item], width),
            })
            .collect();
        let list = List::new(items).block(block).highlight_style(theme::selected()).highlight_symbol("▸");
        frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(Some(self.selected)));
    }
}

fn item_line(item: &Value, width: usize) -> ListItem<'static> {
    let done = item["completed"].truthy();
    let check =
        if done { Span::styled(" ✔ ", Style::new().fg(theme::success()).add_modifier(Modifier::BOLD)) } else { Span::raw(" ☐ ") };
    let title_style = if done { theme::dim().add_modifier(Modifier::CROSSED_OUT) } else { Style::new() };
    let mut spans = vec![check, Span::styled(truncate(&item["title"].s(), width.saturating_sub(24)), title_style)];

    if let Some(due) = item["due_date"].opt().filter(|_| !done) {
        let overdue = due < today().to_string();
        spans.push(Span::styled(
            format!("  📅 {}", short_date(&due)),
            if overdue { Style::new().fg(theme::danger()) } else { theme::dim() },
        ));
    }
    if let Some(name) = item["assignee"]["name"].opt() {
        let first = name.split_whitespace().next().unwrap_or("").to_string();
        spans.push(Span::styled(format!("  @{first}"), Style::new().fg(theme::person_color(&name))));
    }
    if item["recurrence_rule"].truthy() {
        spans.push(Span::styled("  🔁", theme::dim()));
    }
    if item["comments_count"].int() > 0 {
        spans.push(Span::styled(format!("  💬{}", item["comments_count"].int()), theme::dim()));
    }
    ListItem::new(Line::from(spans))
}

/// Reloads the todos on screen, selecting `item` when given.
fn reload(app: &mut App, item: Option<i64>) -> Result<()> {
    let Screen::Todos(screen) = &app.screen else { return Ok(()) };
    let path = format!("/tools/{}/todo", screen.tool["id"].s());
    let fresh = app.get(&path, &[])?;
    if let Screen::Todos(screen) = &mut app.screen {
        screen.replace(fresh["lists"].items().to_vec(), item);
    }
    Ok(())
}

fn update_item(app: &mut App, tool: i64, id: i64, attributes: Value) -> Result<()> {
    app.patch(&format!("/tools/{tool}/todo/items/{id}"), json!({ "item": attributes }))?;
    reload(app, Some(id))
}

pub fn todo_detail(app: &mut App, tool: i64, id: i64) -> Result<Detail> {
    let item = app.get(&format!("/tools/{tool}/todo/items/{id}"), &[])?;
    let mut lines = Vec::new();
    popups::field(&mut lines, "List", item["list"]["title"].opt());
    let status = if item["completed"].truthy() { format!("done {}", ago(&item["completed_at"])) } else { "open".into() };
    popups::field(&mut lines, "Status", Some(status));
    popups::field(&mut lines, "Assignee", item["assignee"]["name"].opt());
    popups::field(&mut lines, "Due", item["due_date"].opt().map(|due| short_date(&due)));
    popups::field(&mut lines, "Repeats", item["recurrence_rule"].opt());
    popups::field(&mut lines, "Created", Some(ago(&item["created_at"])).map(|at| format!("{at} by {}", item["creator"]["name"].s())));

    let description = item["description"].s();
    if !description.trim().is_empty() {
        popups::heading(&mut lines, "Description");
        popups::text(&mut lines, &description, 0);
    }
    popups::comments(&mut lines, &item);
    let attachments = item["attachments"].items();
    if !attachments.is_empty() {
        popups::heading(&mut lines, format!("📎 Attachments ({})", attachments.len()));
        for attachment in attachments {
            lines.push(Line::raw(format!("  {}  {}", attachment["filename"].s(), bytes(&attachment["file_size"]))));
        }
    }

    Ok(Detail {
        title: item["title"].s(),
        lines,
        scroll: 0,
        url: item["url"].opt(),
        comment: Some(CommentOn {
            path: format!("/tools/{tool}/todo/items/{id}/comments"),
            reload: Rc::new(move |app| todo_detail(app, tool, id)),
        }),
    })
}

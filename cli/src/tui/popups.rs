//! Popups over the current screen: help, details, text input, confirmation,
//! search and notifications.

use std::rc::Rc;

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph, Wrap};
use serde_json::{Value, json};

use super::app::{App, Fx, Job, Tone};
use super::theme;
use super::widgets::{TextInput, ago, popup, truncate};
use crate::command::Result;
use crate::value::Json;

pub type Submit = Box<dyn FnOnce(&mut App, String) -> Result<()>>;
pub type ReloadDetail = Rc<dyn Fn(&mut App) -> Result<Detail>>;

pub enum Popup {
    Help { keys: Vec<(&'static str, &'static str)> },
    Detail(Detail),
    Input(Input),
    Confirm { question: String, label: String, job: Option<Job> },
    Search(Search),
    Notifications { items: Vec<Value>, selected: usize },
}

/// A card, todo, message or file, with its text; can take a comment.
pub struct Detail {
    pub title: String,
    pub lines: Vec<Line<'static>>,
    pub scroll: u16,
    pub url: Option<String>,
    pub comment: Option<CommentOn>,
}

/// Where a comment goes, and how to show the detail again afterwards.
#[derive(Clone)]
pub struct CommentOn {
    pub path: String,
    pub reload: ReloadDetail,
}

pub struct Input {
    title: String,
    placeholder: String,
    label: String,
    input: TextInput,
    submit: Option<Submit>,
}

#[derive(Default)]
pub struct Search {
    input: TextInput,
    searched_for: String,
    results: Vec<Value>,
    selected: usize,
}

impl Popup {
    pub fn help(keys: Vec<(&'static str, &'static str)>) -> Self {
        Popup::Help { keys }
    }

    pub fn search() -> Self {
        Popup::Search(Search::default())
    }

    pub fn notifications(items: Vec<Value>) -> Self {
        Popup::Notifications { items, selected: 0 }
    }

    /// Asks for one line of text; `submit` runs as a job with `label` by the spinner.
    pub fn input(title: &str, placeholder: &str, label: &str, submit: impl FnOnce(&mut App, String) -> Result<()> + 'static) -> Self {
        Popup::Input(Input {
            title: title.to_string(),
            placeholder: placeholder.to_string(),
            label: label.to_string(),
            input: TextInput::default(),
            submit: Some(Box::new(submit)),
        })
    }

    pub fn confirm(question: impl Into<String>, label: &str, job: impl FnOnce(&mut App) -> Result<()> + 'static) -> Self {
        Popup::Confirm { question: question.into(), label: label.to_string(), job: Some(Box::new(job)) }
    }
}

pub fn key(popup: &mut Popup, key: KeyEvent, fx: &mut Fx) {
    let close = matches!(key.code, KeyCode::Esc);
    match popup {
        Popup::Help { .. } => {
            if matches!(key.code, KeyCode::Esc | KeyCode::Char('q' | '?') | KeyCode::Enter) {
                fx.close_popup = true;
            }
        }
        Popup::Detail(detail) => match key.code {
            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Enter => fx.close_popup = true,
            KeyCode::Down | KeyCode::Char('j') => detail.scroll = detail.scroll.saturating_add(1),
            KeyCode::Up | KeyCode::Char('k') => detail.scroll = detail.scroll.saturating_sub(1),
            KeyCode::PageDown | KeyCode::Char(' ') => detail.scroll = detail.scroll.saturating_add(10),
            KeyCode::PageUp => detail.scroll = detail.scroll.saturating_sub(10),
            KeyCode::Char('o') => fx.open_url = detail.url.clone(),
            KeyCode::Char('c') => {
                if let Some(comment) = detail.comment.clone() {
                    fx.popup =
                        Some(Popup::input("New comment", "Write a comment and press enter", "Posting your comment", move |app, text| {
                            app.post(&comment.path, json!({ "body": crate::command::paragraphs(&text) }))?;
                            app.popup = Some(Popup::Detail((comment.reload)(app)?));
                            app.toast("Comment posted 💬", Tone::Success);
                            Ok(())
                        }));
                }
            }
            _ => {}
        },
        Popup::Input(input) => match key.code {
            KeyCode::Esc => fx.close_popup = true,
            KeyCode::Enter => {
                if !input.input.is_blank()
                    && let Some(submit) = input.submit.take()
                {
                    let text = input.input.text().trim().to_string();
                    fx.close_popup = true;
                    fx.job(input.label.clone(), move |app| submit(app, text));
                }
            }
            _ => {
                input.input.key(key);
            }
        },
        Popup::Confirm { label, job, .. } => match key.code {
            KeyCode::Char('y' | 'Y') | KeyCode::Enter => {
                fx.close_popup = true;
                if let Some(job) = job.take() {
                    fx.job(label.clone(), job);
                }
            }
            _ => fx.close_popup = true,
        },
        Popup::Search(search) => match key.code {
            _ if close => fx.close_popup = true,
            KeyCode::Down => search.selected = (search.selected + 1).min(search.results.len().saturating_sub(1)),
            KeyCode::Up => search.selected = search.selected.saturating_sub(1),
            KeyCode::Enter => {
                let query = search.input.text().trim().to_string();
                if query != search.searched_for && query.chars().count() >= 2 {
                    search.searched_for = query.clone();
                    fx.job(format!("Searching for “{query}”"), move |app| {
                        let found = app.get("/search", &[("q", query)])?;
                        if let Some(Popup::Search(search)) = app.popup.as_mut() {
                            search.results = found["results"].items().to_vec();
                            search.selected = 0;
                        }
                        Ok(())
                    });
                } else if let Some(result) = search.results.get(search.selected) {
                    fx.open_link = result["url"].opt();
                    fx.close_popup = true;
                }
            }
            _ => {
                search.input.key(key);
            }
        },
        Popup::Notifications { items, selected } => match key.code {
            KeyCode::Esc | KeyCode::Char('q' | 'n') => fx.close_popup = true,
            KeyCode::Down | KeyCode::Char('j') => *selected = (*selected + 1).min(items.len().saturating_sub(1)),
            KeyCode::Up | KeyCode::Char('k') => *selected = selected.saturating_sub(1),
            KeyCode::Enter => {
                if let Some(item) = items.get(*selected) {
                    fx.open_link = item["url"].opt();
                    fx.close_popup = true;
                }
            }
            KeyCode::Char('x') => {
                if let Some(item) = items.get_mut(*selected) {
                    item["read"] = json!(true);
                    let id = item["id"].s();
                    fx.job("Marking it read", move |app| app.post(&format!("/notifications/{id}/read"), json!({})).map(drop));
                }
            }
            KeyCode::Char('a') => {
                for item in items.iter_mut() {
                    item["read"] = json!(true);
                }
                fx.job("Marking everything read", |app| {
                    let result = app.post("/notification_reads", json!({}))?;
                    app.toast(format!("Marked {} read. Inbox zero! 🧘", result["marked_as_read"].int()), Tone::Success);
                    Ok(())
                });
            }
            _ => {}
        },
    }
}

pub fn hints(popup: &Popup) -> Vec<(&'static str, &'static str)> {
    match popup {
        Popup::Help { .. } => vec![("esc", "close")],
        Popup::Detail(detail) => {
            let mut hints = vec![("↑↓", "scroll"), ("o", "open in browser")];
            if detail.comment.is_some() {
                hints.push(("c", "comment"));
            }
            hints.push(("esc", "close"));
            hints
        }
        Popup::Input(_) => vec![("enter", "save"), ("esc", "cancel")],
        Popup::Confirm { .. } => vec![("y", "yes"), ("n", "no")],
        Popup::Search(_) => vec![("enter", "search / open"), ("↑↓", "choose"), ("esc", "close")],
        Popup::Notifications { .. } => vec![("enter", "open"), ("x", "mark read"), ("a", "mark all read"), ("esc", "close")],
    }
}

pub fn draw(popup: &mut Popup, frame: &mut Frame) {
    let screen = frame.area();
    match popup {
        Popup::Help { keys } => {
            let area = popup_area(frame, "Keys", 64, keys.len() as u16 + 9);
            let mut lines: Vec<Line> = keys
                .iter()
                .map(|(key, action)| {
                    Line::from(vec![
                        Span::styled(format!("  {key:<14}"), Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD)),
                        Span::raw(*action),
                    ])
                })
                .collect();
            lines.push(Line::raw(""));
            lines.push(Line::from(Span::styled("  Everywhere: / search  n notifications  ] [ next tool", theme::dim())));
            lines.push(Line::from(Span::styled("  o browser  r reload  esc home  ctrl-c quit", theme::dim())));
            lines.push(Line::raw(""));
            lines.push(Line::from(Span::styled("  For scripts and Claude: dobase help", theme::dim())));
            frame.render_widget(Paragraph::new(lines), area);
        }
        Popup::Detail(detail) => {
            let width = (screen.width * 3 / 4).clamp(50, 100);
            let area = popup_area(frame, &truncate(&detail.title, usize::from(width) - 6), width, screen.height.saturating_sub(4));
            let height = area.height;
            let total = wrapped_height(&detail.lines, area.width);
            let paragraph = Paragraph::new(detail.lines.clone()).wrap(Wrap { trim: false });
            detail.scroll = detail.scroll.min(total.saturating_sub(height));
            frame.render_widget(paragraph.scroll((detail.scroll, 0)), area);
        }
        Popup::Input(input) => {
            let area = popup_area(frame, &input.title, 70, 5);
            let [field, _, hint] = Layout::vertical([Constraint::Length(1), Constraint::Length(1), Constraint::Length(1)]).areas(area);
            frame.render_widget(Span::styled("› ", Style::new().fg(theme::accent())), field);
            let field = ratatui::layout::Rect { x: field.x + 2, width: field.width.saturating_sub(2), ..field };
            input.input.render(frame, field, &input.placeholder, true);
            frame.render_widget(Line::from(Span::styled("enter to save · esc to cancel", theme::dim())), hint);
        }
        Popup::Confirm { question, .. } => {
            let area = popup_area(frame, "Sure?", 60, 5);
            let lines =
                vec![Line::from(question.clone()), Line::raw(""), Line::from(Span::styled("y yes · any other key no", theme::dim()))];
            frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: true }), area);
        }
        Popup::Search(search) => {
            let area = popup_area(frame, "🔎 Search everything", 76, screen.height.saturating_sub(6).min(24));
            let [field, _, results] = Layout::vertical([Constraint::Length(1), Constraint::Length(1), Constraint::Min(1)]).areas(area);
            frame.render_widget(Span::styled("› ", Style::new().fg(theme::accent())), field);
            let field = ratatui::layout::Rect { x: field.x + 2, width: field.width.saturating_sub(2), ..field };
            search.input.render(frame, field, "Cards, todos, docs, files, chat, events, mail…", true);

            if search.results.is_empty() {
                let message = if search.searched_for.is_empty() {
                    "Type at least two letters and press enter."
                } else {
                    "Nothing found. Try another word? 🤔"
                };
                frame.render_widget(Line::from(Span::styled(message, theme::dim())), results);
                return;
            }
            let width = usize::from(results.width);
            let items: Vec<ListItem> = search
                .results
                .iter()
                .map(|result| {
                    ListItem::new(Line::from(vec![
                        Span::styled(format!("{:<9}", result["kind"].s()), theme::dim()),
                        Span::styled(truncate(&result["title"].s(), width.saturating_sub(32)), theme::bold()),
                        Span::styled(format!("  {}", result["tool_name"].s()), theme::dim()),
                    ]))
                })
                .collect();
            let list = List::new(items).highlight_style(theme::selected());
            frame.render_stateful_widget(list, results, &mut ListState::default().with_selected(Some(search.selected)));
        }
        Popup::Notifications { items, selected } => {
            let area = popup_area(frame, "🔔 Notifications", 80, screen.height.saturating_sub(4).min(30));
            if items.is_empty() {
                frame.render_widget(Line::from(Span::styled("Nothing here. All caught up ✨", theme::dim())), area);
                return;
            }
            let width = usize::from(area.width).saturating_sub(4);
            let rows: Vec<ListItem> = items
                .iter()
                .map(|item| {
                    let unread = !item["read"].truthy();
                    let dot = if unread { Span::styled("● ", Style::new().fg(theme::accent())) } else { Span::raw("  ") };
                    ListItem::new(vec![
                        Line::from(vec![
                            dot,
                            Span::styled(truncate(&item["message"].s(), width), if unread { theme::bold() } else { Style::new() }),
                        ]),
                        Line::from(Span::styled(format!("  {}", ago(&item["created_at"])), theme::dim())),
                    ])
                })
                .collect();
            let list = List::new(rows).highlight_style(theme::selected());
            frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(Some(*selected)));
        }
    }
}

/// About how many rows `lines` take when wrapped at `width`.
fn wrapped_height(lines: &[Line], width: u16) -> u16 {
    let width = usize::from(width.max(1));
    lines.iter().map(|line| line.width().max(1).div_ceil(width)).sum::<usize>() as u16
}

fn popup_area(frame: &mut Frame, title: &str, width: u16, height: u16) -> ratatui::layout::Rect {
    let inner = popup(frame, title, width, height);
    inner.inner(ratatui::layout::Margin { horizontal: 1, vertical: 0 })
}

// -- Building details ---------------------------------------------------------

/// "Label  value" in a detail, skipped when there's no value.
pub fn field(lines: &mut Vec<Line<'static>>, label: &str, value: Option<String>) {
    if let Some(value) = value.filter(|value| !value.is_empty()) {
        lines.push(Line::from(vec![Span::styled(format!("{label:<10}"), theme::dim()), Span::raw(value)]));
    }
}

pub fn heading(lines: &mut Vec<Line<'static>>, text: impl Into<String>) {
    lines.push(Line::raw(""));
    lines.push(Line::from(Span::styled(text.into(), Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD))));
}

pub fn text(lines: &mut Vec<Line<'static>>, text: &str, indent: usize) {
    for line in crate::command::clean(text.trim()).lines() {
        lines.push(Line::raw(format!("{}{line}", " ".repeat(indent))));
    }
}

/// Comments under a card or todo.
pub fn comments(lines: &mut Vec<Line<'static>>, record: &Value) {
    let comments = record["comments"].items();
    heading(lines, format!("💬 Comments ({})", comments.len()));
    if comments.is_empty() {
        lines.push(Line::from(Span::styled("  No comments yet. Press c to write the first one.", theme::dim())));
    }
    for comment in comments {
        let author = comment["user"]["name"].opt().unwrap_or_else(|| "Former member".to_string());
        lines.push(Line::raw(""));
        lines.push(Line::from(vec![
            Span::styled(format!("  {author}"), Style::new().fg(theme::person_color(&author)).add_modifier(Modifier::BOLD)),
            Span::styled(format!(" · {}", ago(&comment["created_at"])), theme::dim()),
        ]));
        text(lines, &comment["body"].s(), 2);
    }
}

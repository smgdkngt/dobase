//! A calendar as an agenda: two weeks of events, day by day.

use jiff::civil::Date;
use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState};
use serde_json::Value;

use super::move_selection;
use crate::command::{Result, today};
use crate::tui::app::{App, Fx, Job};
use crate::tui::screens::Screen;
use crate::tui::theme;
use crate::tui::widgets::{local, panel};
use crate::value::Json;

pub const HINTS: [(&str, &str); 5] = [("↑↓", "scroll"), ("h l", "week"), ("t", "today"), ("o", "browser"), ("esc", "home")];

pub const HELP: [(&str, &str); 6] = [
    ("↑ ↓ / j k", "Scroll"),
    ("h l / ← →", "A week earlier or later"),
    ("t", "Back to today"),
    ("o", "Open the calendar in your browser"),
    ("r", "Reload"),
    ("esc", "Back home"),
];

const DAYS: i64 = 14;

pub struct Calendar {
    pub tool: Value,
    start: Date,
    events: Vec<Value>,
    local: bool,
    selected: usize,
}

impl Calendar {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        Self::load_from(app, tool, today())
    }

    fn load_from(app: &mut App, tool: Value, start: Date) -> Result<Self> {
        let end = start.checked_add(jiff::Span::new().days(DAYS - 1)).unwrap_or(start);
        let agenda =
            app.get(&format!("/tools/{}/calendar", tool["id"].s()), &[("start_date", start.to_string()), ("end_date", end.to_string())])?;
        Ok(Self { tool, start, events: agenda["events"].items().to_vec(), local: agenda["local"].truthy(), selected: 0 })
    }

    pub fn refresh(&self) -> Job {
        shift(self.tool.clone(), self.start, 0)
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        match key.code {
            KeyCode::Char('h') | KeyCode::Left => fx.job("Going back a week", shift(self.tool.clone(), self.start, -7)),
            KeyCode::Char('l') | KeyCode::Right => fx.job("Going ahead a week", shift(self.tool.clone(), self.start, 7)),
            KeyCode::Char('t') => fx.job("Back to today", shift(self.tool.clone(), today(), 0)),
            _ => {
                let count = self.rows().len();
                return move_selection(&mut self.selected, count, key);
            }
        }
        true
    }

    /// Day headers and events, in order: (day, Some(event)) for an event.
    fn rows(&self) -> Vec<(Date, Option<&Value>)> {
        let mut rows = Vec::new();
        for offset in 0..DAYS {
            let Ok(day) = self.start.checked_add(jiff::Span::new().days(offset)) else { break };
            let events: Vec<&Value> = self.events.iter().filter(|event| on_day(event, day)).collect();
            if events.is_empty() && day != today() {
                continue;
            }
            rows.push((day, None));
            rows.extend(events.into_iter().map(|event| (day, Some(event))));
        }
        rows
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        let end = self.start.checked_add(jiff::Span::new().days(DAYS - 1)).unwrap_or(self.start);
        let title = format!(
            "{} {} · {} – {}",
            theme::tool_icon("calendar"),
            self.tool["name"].s(),
            self.start.strftime("%-d %b"),
            end.strftime("%-d %b")
        );
        let rows = self.rows();
        let now = jiff::Zoned::now();

        let items: Vec<ListItem> = rows
            .iter()
            .map(|(day, event)| match event {
                None => {
                    let label = if *day == today() { format!("Today · {}", day.strftime("%A %-d %B")) } else { day.strftime("%A %-d %B").to_string() };
                    let style = if *day == today() { Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD) } else { theme::bold() };
                    let mut lines = vec![Line::raw(""), Line::from(Span::styled(label, style))];
                    if *day == today() && !rows.iter().any(|(other, event)| other == day && event.is_some()) {
                        lines.push(Line::from(Span::styled("  Nothing today. Free as a bird 🐦", theme::dim())));
                    }
                    ListItem::new(lines)
                }
                Some(event) => {
                    let starts = event["starts_at"].s();
                    let ends = event["ends_at"].s();
                    let time = if event["all_day"].truthy() {
                        "all day    ".to_string()
                    } else {
                        format!("{}–{}", starts.chars().skip(11).take(5).collect::<String>(), ends.chars().skip(11).take(5).collect::<String>())
                    };
                    let happening = !event["all_day"].truthy()
                        && matches!((local(&event["starts_at"]), local(&event["ends_at"])), (Some(from), Some(till)) if from <= now && now < till);
                    let mut spans = vec![
                        Span::styled(format!("  {time}  "), if happening { Style::new().fg(theme::success()).add_modifier(Modifier::BOLD) } else { theme::dim() }),
                        Span::styled(event["summary"].s(), theme::bold()),
                    ];
                    if let Some(calendar) = event["calendar"]["name"].opt() {
                        spans.push(Span::styled(format!("  {calendar}"), Style::new().fg(theme::person_color(&calendar))));
                    }
                    if let Some(location) = event["location"].opt().filter(|location| !location.is_empty()) {
                        spans.push(Span::styled(format!("  📍 {location}"), theme::dim()));
                    }
                    if event["recurring"].truthy() {
                        spans.push(Span::styled("  🔁", theme::dim()));
                    }
                    if happening {
                        spans.push(Span::styled("  ● now", Style::new().fg(theme::success())));
                    }
                    ListItem::new(Line::from(spans))
                }
            })
            .collect();

        let mut block = panel(title, true);
        if self.local {
            block = block.title_bottom(Line::from(Span::styled(" kept in Dobase ", theme::dim())).right_aligned());
        }
        self.selected = self.selected.min(rows.len().saturating_sub(1));
        let list = List::new(items).block(block).highlight_style(Style::new().add_modifier(Modifier::REVERSED));
        frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(Some(self.selected)));
    }
}

/// A job showing the two weeks from `start` moved by `days`.
fn shift(tool: Value, start: Date, days: i64) -> Job {
    Box::new(move |app: &mut App| {
        let start = start.checked_add(jiff::Span::new().days(days)).unwrap_or(start);
        let fresh = Calendar::load_from(app, tool, start)?;
        if let Screen::Calendar(calendar) = &mut app.screen {
            let selected = if days == 0 { calendar.selected } else { 0 };
            *calendar = Calendar { selected, ..fresh };
        }
        Ok(())
    })
}

/// Whether `event` takes place on `day` (it may span several).
fn on_day(event: &Value, day: Date) -> bool {
    let date = |value: &Value| value.s().chars().take(10).collect::<String>().parse::<Date>().ok();
    match (date(&event["starts_at"]), date(&event["ends_at"])) {
        (Some(starts), Some(ends)) => starts <= day && day <= ends.max(starts),
        _ => false,
    }
}

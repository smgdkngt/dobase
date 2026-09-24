//! Home: the logo, a hello, your tools and what's new.

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph};
use serde_json::{Value, json};

use super::{View, move_selection};
use crate::command::Result;
use crate::tui::app::{App, Fx, Tone};
use crate::tui::theme;
use crate::tui::widgets::{ago, panel, truncate};
use crate::value::Json;

pub const HELP: [(&str, &str); 12] = [
    ("↑↓ / j k", "Choose a tool"),
    ("enter", "Open it"),
    ("1-9", "Open the first nine tools"),
    ("tab", "Switch between tools and notifications"),
    ("x", "Mark the chosen notification read"),
    ("] [", "Next or previous tool, from anywhere"),
    ("/", "Search everything"),
    ("n", "Notifications"),
    ("o", "Open Dobase in your browser"),
    ("r", "Reload"),
    ("esc / g", "Back home, from anywhere"),
    ("q", "Quit"),
];

#[derive(Default)]
pub struct Home {
    pub selected: usize,
    notifications: Vec<Value>,
    notification: usize,
    on_notifications: bool,
}

/// How many notifications home shows.
pub const NOTIFICATIONS: usize = 12;

impl Home {
    pub fn load(app: &mut App) -> Result<Self> {
        let notifications = app.get("/notifications", &[("limit", NOTIFICATIONS.to_string())])?.items().to_vec();
        Ok(Self { notifications, ..Self::default() })
    }

    pub fn replace_notifications(&mut self, notifications: Vec<Value>) {
        let selected = self.notifications.get(self.notification).map(|notification| notification["id"].int());
        self.notifications = notifications;
        self.notification =
            selected.and_then(|id| self.notifications.iter().position(|notification| notification["id"].int() == id)).unwrap_or(0);
    }

    pub fn key(&mut self, key: KeyEvent, view: &View, fx: &mut Fx) -> bool {
        match key.code {
            KeyCode::Tab | KeyCode::BackTab => {
                self.on_notifications = !self.on_notifications && !self.notifications.is_empty();
                true
            }
            KeyCode::Char(digit @ '1'..='9') => {
                let index = digit as usize - '1' as usize;
                if let Some(tool) = view.tools.get(index) {
                    fx.open_tool = Some(tool["id"].int());
                }
                true
            }
            KeyCode::Enter | KeyCode::Char('l') | KeyCode::Right if !self.on_notifications => {
                if let Some(tool) = view.tools.get(self.selected) {
                    fx.open_tool = Some(tool["id"].int());
                }
                true
            }
            KeyCode::Enter if self.on_notifications => {
                if let Some(notification) = self.notifications.get_mut(self.notification) {
                    open_notification(notification, fx);
                }
                true
            }
            KeyCode::Char('x') if self.on_notifications => {
                if let Some(notification) = self.notifications.get_mut(self.notification) {
                    let id = notification["id"].s();
                    notification["read"] = json!(true);
                    fx.job("Marking it read", move |app| {
                        app.post(&format!("/notifications/{id}/read"), json!({}))?;
                        Ok(())
                    });
                }
                true
            }
            _ if self.on_notifications => move_selection(&mut self.notification, self.notifications.len(), key),
            _ => move_selection(&mut self.selected, view.tools.len(), key),
        }
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect, view: &View) {
        let compact = area.height < 18;
        let logo_height = if compact { 0 } else { 6 };
        let [logo_area, hello_area, lists_area, tip_area] =
            Layout::vertical([Constraint::Length(logo_height), Constraint::Length(3), Constraint::Min(5), Constraint::Length(1)])
                .areas(area);

        if !compact {
            let logo = Paragraph::new(theme::logo(view.tick)).centered();
            frame.render_widget(logo, logo_area.inner(ratatui::layout::Margin { horizontal: 0, vertical: 0 }));
        }

        let hour = jiff::Zoned::now().hour();
        let first_name = view.me["name"].s().split_whitespace().next().unwrap_or("there").to_string();
        let unread = self.notifications.iter().filter(|notification| !notification["read"].truthy()).count();
        let summary = match unread {
            0 => format!("{} tools · nothing new, enjoy the quiet", view.tools.len()),
            1 => format!("{} tools · 1 new notification", view.tools.len()),
            count => format!("{} tools · {count} new notifications", view.tools.len()),
        };
        let hello = Paragraph::new(vec![
            Line::from(Span::styled(theme::greeting(hour, &first_name), theme::bold())),
            Line::from(Span::styled(summary, theme::dim())),
        ])
        .centered();
        frame.render_widget(hello, hello_area);

        let [tools_area, notifications_area] =
            Layout::horizontal([Constraint::Percentage(45), Constraint::Percentage(55)]).spacing(1).areas(lists_area);
        self.draw_tools(frame, tools_area, view);
        self.draw_notifications(frame, notifications_area);

        let tip = theme::TIPS[(view.tick / 100) as usize % theme::TIPS.len()];
        frame.render_widget(Line::from(Span::styled(format!("💡 {tip}"), theme::dim())).centered(), tip_area);
    }

    fn draw_tools(&mut self, frame: &mut Frame, area: Rect, view: &View) {
        let width = usize::from(area.width.saturating_sub(4));
        let items: Vec<ListItem> = view
            .tools
            .iter()
            .enumerate()
            .map(|(index, tool)| {
                let number = if index < 9 { format!("{} ", index + 1) } else { "  ".to_string() };
                let kind = tool["type"].s();
                let name = truncate(&tool["name"].s(), width.saturating_sub(18));
                let mut spans = vec![
                    Span::styled(number, theme::dim()),
                    Span::raw(format!("{} ", theme::tool_icon(&kind))),
                    Span::styled(name, theme::bold()),
                    Span::styled(format!("  {kind}"), theme::dim()),
                ];
                if tool["unread"].truthy() {
                    spans.push(Span::styled(" ●", Style::new().fg(theme::accent())));
                }
                ListItem::new(Line::from(spans))
            })
            .collect();

        let list = List::new(items)
            .block(panel("Your tools", !self.on_notifications))
            .highlight_style(if self.on_notifications { Style::new().add_modifier(Modifier::BOLD) } else { theme::selected() })
            .highlight_symbol("▸ ");
        if view.tools.is_empty() {
            let empty = Paragraph::new("No tools yet. Make one in the browser, or: dobase tool create")
                .style(theme::dim())
                .block(panel("Your tools", true));
            frame.render_widget(empty, area);
            return;
        }
        self.selected = self.selected.min(view.tools.len() - 1);
        frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(Some(self.selected)));
    }

    fn draw_notifications(&mut self, frame: &mut Frame, area: Rect) {
        let block = panel("What's new", self.on_notifications);
        if self.notifications.is_empty() {
            let empty = Paragraph::new(vec![Line::raw(""), Line::from("  All caught up ✨").style(theme::dim())]).block(block);
            frame.render_widget(empty, area);
            return;
        }

        let width = usize::from(area.width.saturating_sub(6));
        let items: Vec<ListItem> = self
            .notifications
            .iter()
            .map(|notification| {
                let unread = !notification["read"].truthy();
                let dot = if unread { Span::styled("● ", Style::new().fg(theme::accent())) } else { Span::raw("  ") };
                let message =
                    Span::styled(truncate(&notification["message"].s(), width), if unread { theme::bold() } else { Style::new() });
                let when = ago(&notification["created_at"]);
                ListItem::new(vec![Line::from(vec![dot, message]), Line::from(Span::styled(format!("  {when}"), theme::dim()))])
            })
            .collect();
        let list = List::new(items).block(block).highlight_style(if self.on_notifications { theme::selected() } else { Style::new() });
        self.notification = self.notification.min(self.notifications.len() - 1);
        let selected = self.on_notifications.then_some(self.notification);
        frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(selected));
    }
}

/// The tool id in a Dobase URL such as /tools/12/board?card=3.
pub fn tool_id_in(url: &str) -> Option<i64> {
    let rest = url.split("/tools/").nth(1)?;
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok()
}

/// Opens what a notification is about, and marks it read like the web app does.
pub fn open_notification(notification: &mut Value, fx: &mut Fx) {
    if !notification["read"].truthy() {
        notification["read"] = json!(true);
        let id = notification["id"].s();
        fx.job("Marking it read", move |app| app.post(&format!("/notifications/{id}/read"), json!({})).map(drop));
    }
    match notification["url"].opt() {
        Some(url) => fx.open_link = Some(url),
        None => fx.toast("That notification doesn't lead anywhere.", Tone::Info),
    }
}

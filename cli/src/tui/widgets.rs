//! Small pieces the screens share: a text field, confetti, popups and key hints.

use std::time::{Duration, Instant};

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::layout::{Constraint, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Clear};

use super::theme;

/// A one-line text field.
#[derive(Default, Clone)]
pub struct TextInput {
    chars: Vec<char>,
    cursor: usize,
}

impl TextInput {
    /// A field that starts with `text`, the cursor at its end.
    pub fn with(text: &str) -> Self {
        let chars: Vec<char> = text.chars().collect();
        Self { cursor: chars.len(), chars }
    }

    pub fn text(&self) -> String {
        self.chars.iter().collect()
    }

    pub fn is_blank(&self) -> bool {
        self.chars.iter().all(|char| char.is_whitespace())
    }

    pub fn clear(&mut self) {
        self.chars.clear();
        self.cursor = 0;
    }

    /// Handles editing keys; returns false for keys it leaves to the caller (Enter, Esc, ...).
    pub fn key(&mut self, key: KeyEvent) -> bool {
        let control = key.modifiers.contains(KeyModifiers::CONTROL);
        match key.code {
            KeyCode::Char('u') if control => {
                self.chars.drain(..self.cursor);
                self.cursor = 0;
            }
            KeyCode::Char('w') if control => {
                let mut start = self.cursor;
                while start > 0 && self.chars[start - 1] == ' ' {
                    start -= 1;
                }
                while start > 0 && self.chars[start - 1] != ' ' {
                    start -= 1;
                }
                self.chars.drain(start..self.cursor);
                self.cursor = start;
            }
            KeyCode::Char('a') if control => self.cursor = 0,
            KeyCode::Char('e') if control => self.cursor = self.chars.len(),
            KeyCode::Char(char) if !control => {
                self.chars.insert(self.cursor, char);
                self.cursor += 1;
            }
            KeyCode::Backspace if self.cursor > 0 => {
                self.cursor -= 1;
                self.chars.remove(self.cursor);
            }
            KeyCode::Delete if self.cursor < self.chars.len() => {
                self.chars.remove(self.cursor);
            }
            KeyCode::Left => self.cursor = self.cursor.saturating_sub(1),
            KeyCode::Right => self.cursor = (self.cursor + 1).min(self.chars.len()),
            KeyCode::Home => self.cursor = 0,
            KeyCode::End => self.cursor = self.chars.len(),
            KeyCode::Backspace | KeyCode::Delete => {}
            _ => return false,
        }
        true
    }

    /// Draws the text in `area` (one line), scrolled so the cursor shows, and places the cursor.
    pub fn render(&self, frame: &mut Frame, area: Rect, placeholder: &str, focused: bool) {
        let width = usize::from(area.width.max(1));
        let start = (self.cursor + 1).saturating_sub(width);
        let line = if self.chars.is_empty() && !placeholder.is_empty() {
            Line::from(Span::styled(placeholder.to_string(), theme::dim()))
        } else {
            Line::from(self.chars[start..].iter().collect::<String>())
        };
        frame.render_widget(line, area);
        if focused {
            let before: String = self.chars[start..self.cursor].iter().collect();
            let offset = ratatui::text::Line::from(before).width() as u16;
            frame.set_cursor_position((area.x + offset.min(area.width.saturating_sub(1)), area.y));
        }
    }
}

/// A short burst of confetti over the screen when something gets done.
pub struct Confetti {
    started: Instant,
    seed: u64,
}

impl Confetti {
    const LENGTH: Duration = Duration::from_millis(1400);

    pub fn new(seed: u64) -> Self {
        Self { started: Instant::now(), seed }
    }

    pub fn finished(&self) -> bool {
        self.started.elapsed() > Self::LENGTH
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        if area.width < 4 || area.height < 4 {
            return;
        }
        let progress = self.started.elapsed().as_secs_f32() / Self::LENGTH.as_secs_f32();
        let colors = [(239, 68, 68), (234, 179, 8), (34, 197, 94), (59, 130, 246), (168, 85, 247), (236, 72, 153)];
        let pieces = ['✦', '•', '*', '▪', '✧', '◆', '~'];
        let mut state = self.seed | 1;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };

        let buffer = frame.buffer_mut();
        for _ in 0..(area.width as usize * 2).min(160) {
            let x = next() % u64::from(area.width);
            let speed = 0.6 + (next() % 100) as f32 / 100.0;
            let drift = (next() % 7) as i32 - 3;
            let start_row = (next() % u64::from(area.height / 2)) as f32 - area.height as f32 / 2.0;
            let row = start_row + progress * speed * area.height as f32 * 1.4;
            let column = x as i32 + (drift as f32 * progress * 3.0) as i32;
            if row < 0.0 || row >= area.height as f32 || column < 0 || column >= i32::from(area.width) {
                continue;
            }
            let (r, g, b) = colors[(next() % colors.len() as u64) as usize];
            let piece = pieces[(next() % pieces.len() as u64) as usize];
            let position = (area.x + column as u16, area.y + row as u16);
            if let Some(cell) = buffer.cell_mut(position) {
                cell.set_char(piece).set_style(Style::new().fg(theme::rgb(r, g, b)).add_modifier(Modifier::BOLD));
            }
        }
    }
}

/// Clears and frames a centered popup, returning the area inside the frame.
pub fn popup(frame: &mut Frame, title: &str, width: u16, height: u16) -> Rect {
    let screen = frame.area();
    let area = screen.centered(
        Constraint::Length(width.min(screen.width.saturating_sub(2))),
        Constraint::Length(height.min(screen.height.saturating_sub(2))),
    );
    frame.render_widget(Clear, area);
    let block = Block::new()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(theme::accent()))
        .title(Span::styled(format!(" {title} "), theme::bold()));
    let inner = block.inner(area);
    frame.render_widget(block, area);
    inner
}

/// "key action · key action" for the bottom bar.
pub fn hints(pairs: &[(&str, &str)]) -> Line<'static> {
    let mut spans = Vec::new();
    for (index, (key, action)) in pairs.iter().enumerate() {
        if index > 0 {
            spans.push(Span::styled("  ", theme::dim()));
        }
        spans.push(Span::styled(key.to_string(), Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD)));
        spans.push(Span::styled(format!(" {action}"), theme::dim()));
    }
    Line::from(spans)
}

/// A rounded panel with a title; highlighted when it has the focus.
pub fn panel(title: impl Into<String>, focused: bool) -> Block<'static> {
    let color = if focused { theme::accent() } else { theme::muted() };
    Block::new()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(color))
        .title(Span::styled(format!(" {} ", title.into()), if focused { theme::bold() } else { Style::new() }))
}

/// Wraps text to `width` columns, keeping paragraphs.
pub fn wrap(text: &str, width: usize) -> Vec<String> {
    let width = width.max(8);
    let mut lines = Vec::new();
    for paragraph in text.trim_end().split('\n') {
        let mut line = String::new();
        for word in paragraph.split(' ') {
            let fits = Line::from(format!("{line} {word}")).width() <= width;
            if line.is_empty() {
                line = word.to_string();
            } else if fits {
                line.push(' ');
                line.push_str(word);
            } else {
                lines.push(std::mem::take(&mut line));
                line = word.to_string();
            }
            while Line::from(line.as_str()).width() > width {
                let cut: String = line.chars().take(width).collect();
                let rest: String = line.chars().skip(width).collect();
                lines.push(cut);
                line = rest;
            }
        }
        lines.push(line);
    }
    lines
}

/// Cuts text to `width` columns with an ellipsis.
pub fn truncate(text: &str, width: usize) -> String {
    if Line::from(text).width() <= width {
        return text.to_string();
    }
    let mut out = String::new();
    for char in text.chars() {
        if Line::from(format!("{out}{char}…")).width() > width {
            break;
        }
        out.push(char);
    }
    out.push('…');
    out
}

/// A server timestamp the way people say it: "just now", "12 min ago", "yesterday 14:05", "Sep 20".
pub fn ago(value: &serde_json::Value) -> String {
    use crate::value::Json;
    let text = value.s();
    let Ok(timestamp) = text.parse::<jiff::Timestamp>() else { return crate::command::moment(value).unwrap_or_default() };
    let now = jiff::Zoned::now();
    let then = timestamp.to_zoned(now.time_zone().clone());
    let minutes = now.timestamp().duration_since(timestamp).as_secs() / 60;
    let days = then.date().until(now.date()).map(|span| span.get_days()).unwrap_or(0);
    match (minutes, days) {
        (..1, _) => "just now".to_string(),
        (1..60, _) => format!("{minutes} min ago"),
        (_, 0) => format!("today {}", then.strftime("%H:%M")),
        (_, 1) => format!("yesterday {}", then.strftime("%H:%M")),
        (_, 2..7) => then.strftime("%A %H:%M").to_string(),
        _ if then.year() == now.year() => then.strftime("%b %-d").to_string(),
        _ => then.strftime("%b %-d, %Y").to_string(),
    }
}

/// A server timestamp in this computer's time zone.
pub fn local(value: &serde_json::Value) -> Option<jiff::Zoned> {
    use crate::value::Json;
    let timestamp = value.s().parse::<jiff::Timestamp>().ok()?;
    Some(timestamp.to_zoned(jiff::tz::TimeZone::system()))
}

/// A due date as people type it: today, tomorrow, a weekday (the next one),
/// +3 (days from now), 2026-10-01, or none to clear it.
pub fn due_date(text: &str) -> std::result::Result<Option<jiff::civil::Date>, String> {
    use jiff::civil::Weekday;
    let text = text.trim().to_lowercase();
    let today = crate::command::today();
    let days = |count: i64| today.checked_add(jiff::Span::new().days(count)).ok();
    let weekday = match text.get(..3).unwrap_or("") {
        "mon" | "maa" => Some(Weekday::Monday),
        "tue" | "din" => Some(Weekday::Tuesday),
        "wed" | "woe" => Some(Weekday::Wednesday),
        "thu" | "don" => Some(Weekday::Thursday),
        "fri" | "vri" => Some(Weekday::Friday),
        "sat" | "zat" => Some(Weekday::Saturday),
        "sun" | "zon" => Some(Weekday::Sunday),
        _ => None,
    };
    let date = match text.as_str() {
        "" | "none" | "-" => return Ok(None),
        "today" | "vandaag" => Some(today),
        "tomorrow" | "morgen" => days(1),
        "next week" => days(7),
        _ if text.starts_with('+') => text[1..].trim_end_matches('d').parse::<i64>().ok().and_then(days),
        _ if weekday.is_some() => {
            let target = weekday.unwrap().to_monday_one_offset();
            let ahead = (i64::from(target) - i64::from(today.weekday().to_monday_one_offset())).rem_euclid(7);
            days(if ahead == 0 { 7 } else { ahead })
        }
        _ => text.parse::<jiff::civil::Date>().ok(),
    };
    date.map(Some).ok_or_else(|| format!("“{text}” isn't a date. Try fri, +3, tomorrow or 2026-10-01."))
}

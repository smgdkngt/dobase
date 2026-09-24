//! Colors, the logo and the little bits of personality.

use std::sync::OnceLock;

use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};

pub const LOGO: [&str; 5] = [
    r"     _       _                    ",
    r"  __| | ___ | |__   __ _ ___  ___ ",
    r" / _` |/ _ \| '_ \ / _` / __|/ _ \",
    r"| (_| | (_) | |_) | (_| \__ \  __/",
    r" \__,_|\___/|_.__/ \__,_|___/\___|",
];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Depth {
    None,
    Indexed,
    True,
}

/// NO_COLOR turns colors off; terminals that don't say they do 24-bit color get the 256-color palette.
fn depth() -> Depth {
    static DEPTH: OnceLock<Depth> = OnceLock::new();
    *DEPTH.get_or_init(|| {
        if std::env::var_os("NO_COLOR").is_some_and(|value| !value.is_empty()) {
            Depth::None
        } else if std::env::var("COLORTERM").is_ok_and(|value| value.contains("truecolor") || value.contains("24bit")) {
            Depth::True
        } else {
            Depth::Indexed
        }
    })
}

pub fn rgb(r: u8, g: u8, b: u8) -> Color {
    match depth() {
        Depth::None => Color::Reset,
        Depth::True => Color::Rgb(r, g, b),
        Depth::Indexed => {
            let level = |value: u8| {
                if value < 48 {
                    0
                } else if value < 115 {
                    1
                } else {
                    (value - 35) / 40
                }
            };
            Color::Indexed(16 + 36 * level(r) + 6 * level(g) + level(b))
        }
    }
}

pub fn accent() -> Color {
    rgb(59, 130, 246)
}

pub fn muted() -> Color {
    rgb(128, 128, 140)
}

pub fn success() -> Color {
    rgb(34, 197, 94)
}

pub fn warning() -> Color {
    rgb(245, 158, 11)
}

pub fn danger() -> Color {
    rgb(239, 68, 68)
}

pub fn dim() -> Style {
    Style::new().fg(muted())
}

pub fn bold() -> Style {
    Style::new().add_modifier(Modifier::BOLD)
}

/// The selected row: reversed, so it shows even without color.
pub fn selected() -> Style {
    Style::new().bg(accent()).fg(Color::White).add_modifier(Modifier::BOLD)
}

/// A card's color, as the app names them.
pub fn card_color(name: &str) -> Option<Color> {
    Some(match name {
        "red" => rgb(239, 68, 68),
        "orange" => rgb(249, 115, 22),
        "yellow" => rgb(234, 179, 8),
        "green" => rgb(34, 197, 94),
        "blue" => rgb(59, 130, 246),
        "purple" => rgb(168, 85, 247),
        _ => return None,
    })
}

/// A steady color per person, so a chat reads at a glance.
pub fn person_color(name: &str) -> Color {
    const PALETTE: [(u8, u8, u8); 8] =
        [(96, 165, 250), (244, 114, 182), (52, 211, 153), (251, 191, 36), (167, 139, 250), (248, 113, 113), (45, 212, 191), (251, 146, 60)];
    let hash = name.bytes().fold(7u32, |hash, byte| hash.wrapping_mul(31).wrapping_add(u32::from(byte)));
    let (r, g, b) = PALETTE[hash as usize % PALETTE.len()];
    rgb(r, g, b)
}

/// The logo in a blue-to-pink gradient that drifts slowly with `tick`.
pub fn logo(tick: u64) -> Vec<Line<'static>> {
    let width = LOGO[0].chars().count() as f32;
    LOGO.iter()
        .enumerate()
        .map(|(row, line)| {
            Line::from(
                line.chars()
                    .enumerate()
                    .map(|(column, char)| {
                        let phase = ((column as f32 + row as f32 * 2.0) / width + tick as f32 / 40.0).fract();
                        let wave = if phase < 0.5 { phase * 2.0 } else { (1.0 - phase) * 2.0 };
                        let mix = |from: f32, to: f32| (from + (to - from) * wave) as u8;
                        let color = rgb(mix(59.0, 236.0), mix(130.0, 72.0), mix(246.0, 153.0));
                        Span::styled(char.to_string(), Style::new().fg(color).add_modifier(Modifier::BOLD))
                    })
                    .collect::<Vec<_>>(),
            )
        })
        .collect()
}

pub fn tool_icon(kind: &str) -> &'static str {
    match kind {
        "boards" => "📋",
        "todos" => "✅",
        "docs" => "📝",
        "chat" => "💬",
        "files" => "📁",
        "mail" => "📬",
        "calendar" => "📅",
        "room" => "🎥",
        _ => "🧰",
    }
}

pub fn greeting(hour: i8, name: &str) -> String {
    let (hello, emoji) = match hour {
        5..=11 => ("Good morning", "🌅"),
        12..=17 => ("Good afternoon", "🌞"),
        18..=22 => ("Good evening", "🌙"),
        _ => ("Burning the midnight oil", "🦉"),
    };
    format!("{hello}, {name} {emoji}")
}

/// Said when something gets done.
pub const CHEERS: [&str; 8] = [
    "Nice one! 🎉",
    "Done and dusted ✨",
    "Look at you go 🚀",
    "Another one bites the dust 💪",
    "Shipped! 🚢",
    "Crushing it 🔥",
    "Tick! ✔",
    "High five 🙌",
];

pub const TIPS: [&str; 7] = [
    "Press / to search everything you share.",
    "Press ? any time to see the keys.",
    "Press o to open what you're looking at in the browser.",
    "Press ] and [ to hop between tools.",
    "On a board, H and L move a card to the next column.",
    "In a todo list, space ticks a todo off.",
    "Scripts and Claude can use the same tool: dobase help.",
];

/// A column where finished work goes, which earns confetti.
pub fn is_done_column(name: &str) -> bool {
    let name = name.to_lowercase();
    ["done", "shipped", "klaar", "finished", "complete", "live"].iter().any(|word| name.contains(word))
}

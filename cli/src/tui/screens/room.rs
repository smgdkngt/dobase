//! A video room, which only works in the browser.

use ratatui::Frame;
use ratatui::layout::{Constraint, Rect};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use serde_json::Value;

use crate::tui::theme;
use crate::tui::widgets::panel;
use crate::value::Json;

const CAMERA: [&str; 7] = [
    ".-------------------.    ",
    "|  .-----------.    |==. ",
    "|  |           |    |  | ",
    "|  |   (•‿•)   |    |==' ",
    "|  |           |    |    ",
    "|  '-----------'    |    ",
    "'-------------------'    ",
];

pub struct Room {
    pub tool: Value,
}

impl Room {
    pub fn draw(&self, frame: &mut Frame, area: Rect) {
        let block = panel(format!("{} {}", theme::tool_icon("room"), self.tool["name"].s()), true);
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let mut lines: Vec<Line> = CAMERA.iter().map(|line| Line::from(Span::styled(*line, theme::dim()))).collect();
        lines.push(Line::raw(""));
        lines.push(Line::from(Span::styled("Rooms need a camera, so they live in the browser.", theme::bold())));
        lines.push(Line::from(Span::styled("Press o to join. Don't forget to fix your hair 💇", theme::dim())));
        let height = lines.len() as u16;
        let area = inner.centered_vertically(Constraint::Length(height));
        frame.render_widget(Paragraph::new(lines).centered(), area);
    }
}

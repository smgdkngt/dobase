//! Files: walk through the folders, look at a file, download it.

use std::path::PathBuf;

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph};
use serde_json::Value;

use super::move_selection;
use crate::command::{Result, bytes, day};
use crate::tui::app::{App, Fx, Job, Tone};
use crate::tui::popups::{self, Detail, Popup};
use crate::tui::screens::Screen;
use crate::tui::theme;
use crate::tui::widgets::{ago, panel, truncate};
use crate::value::Json;

pub const HINTS: [(&str, &str); 6] =
    [("↑↓", "choose"), ("enter", "open"), ("⌫", "up"), ("d", "download"), ("o", "browser"), ("esc", "home")];

pub const HELP: [(&str, &str); 7] = [
    ("↑ ↓ / j k", "Choose a folder or file"),
    ("enter / →", "Open the folder, or show the file"),
    ("⌫ / ←", "Up one folder"),
    ("d", "Download the file into the folder you started dobase in"),
    ("o", "Open it in your browser"),
    ("r", "Reload"),
    ("esc", "Back home"),
];

pub struct Files {
    pub tool: Value,
    listing: Value,
    folder: Option<i64>,
    selected: usize,
}

enum Entry<'a> {
    Folder(&'a Value),
    File(&'a Value),
}

impl Files {
    pub fn load(app: &mut App, tool: Value) -> Result<Self> {
        Self::load_folder(app, tool, None)
    }

    pub fn load_folder(app: &mut App, tool: Value, folder: Option<i64>) -> Result<Self> {
        let params: Vec<(&str, String)> = folder.map(|id| ("folder_id", id.to_string())).into_iter().collect();
        let listing = app.get(&format!("/tools/{}/files", tool["id"].s()), &params)?;
        Ok(Self { tool, listing, folder, selected: 0 })
    }

    fn entries(&self) -> Vec<Entry<'_>> {
        let folders = self.listing["folders"].items().iter().map(Entry::Folder);
        folders.chain(self.listing["files"].items().iter().map(Entry::File)).collect()
    }

    pub fn refresh(&self) -> Job {
        let (tool, folder, selected) = (self.tool.clone(), self.folder, self.selected);
        Box::new(move |app: &mut App| {
            let mut fresh = Files::load_folder(app, tool, folder)?;
            fresh.selected = selected;
            app.screen = Screen::Files(fresh);
            Ok(())
        })
    }

    fn go(&self, folder: Option<i64>, fx: &mut Fx) {
        let tool = self.tool.clone();
        fx.job("Opening the folder", move |app| {
            let fresh = Files::load_folder(app, tool, folder)?;
            app.screen = Screen::Files(fresh);
            Ok(())
        });
    }

    pub fn key(&mut self, key: KeyEvent, fx: &mut Fx) -> bool {
        let tool = self.tool["id"].int();
        match key.code {
            KeyCode::Enter | KeyCode::Right | KeyCode::Char('l') => match self.entries().get(self.selected) {
                Some(Entry::Folder(folder)) => self.go(Some(folder["id"].int()), fx),
                Some(Entry::File(file)) => fx.popup = Some(Popup::Detail(file_detail(file))),
                None => {}
            },
            KeyCode::Backspace | KeyCode::Left | KeyCode::Char('h') => {
                if self.folder.is_some() {
                    let parent = self.listing["folder"]["parent_id"].opt().and_then(|id| id.parse().ok());
                    self.go(parent, fx);
                }
            }
            KeyCode::Char('d') => {
                if let Some(Entry::File(file)) = self.entries().get(self.selected) {
                    let (id, name) = (file["id"].int(), file["name"].s());
                    let destination = download_path(&name);
                    fx.popup =
                        Some(Popup::confirm(format!("Download “{name}” to {}?", destination.display()), "Downloading", move |app| {
                            app.api.download(&format!("/tools/{tool}/files/items/{id}/download"), &destination)?;
                            app.toast(format!("Saved to {} 📥", destination.display()), Tone::Success);
                            Ok(())
                        }));
                }
            }
            KeyCode::Char('o') => {
                let url = match (self.entries().get(self.selected), self.folder) {
                    (Some(Entry::Folder(folder)), _) => format!("/tools/{tool}/files?folder_id={}", folder["id"].s()),
                    (_, Some(folder)) => format!("/tools/{tool}/files?folder_id={folder}"),
                    _ => format!("/tools/{tool}/files"),
                };
                fx.open_url = Some(url);
            }
            _ => {
                let count = self.entries().len();
                return move_selection(&mut self.selected, count, key);
            }
        }
        true
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect) {
        let mut trail = vec![self.tool["name"].s()];
        trail.extend(self.listing["breadcrumbs"].items().iter().map(|crumb| crumb["name"].s()));
        trail.extend(self.listing["folder"]["name"].opt());
        let block = panel(format!("{} {}", theme::tool_icon("files"), trail.join(" / ")), true);

        let entries = self.entries();
        if entries.is_empty() {
            let message = if self.folder.is_some() {
                "This folder is empty. ⌫ to go up."
            } else {
                "No files yet. Drop some in with: dobase file upload"
            };
            frame.render_widget(Paragraph::new(message).style(theme::dim()).block(block), area);
            return;
        }
        let width = usize::from(area.width.saturating_sub(34));
        let items: Vec<ListItem> = entries
            .iter()
            .map(|entry| match entry {
                Entry::Folder(folder) => ListItem::new(Line::from(vec![
                    Span::raw(" 📂 "),
                    Span::styled(truncate(&folder["name"].s(), width), Style::new().add_modifier(Modifier::BOLD)),
                    Span::styled(if folder["shared"].truthy() { "  🔗" } else { "" }, theme::dim()),
                ])),
                Entry::File(file) => ListItem::new(Line::from(vec![
                    Span::raw(format!(" {} ", file_icon(&file["name"].s()))),
                    Span::raw(format!("{:<width$}", truncate(&file["name"].s(), width))),
                    Span::styled(
                        format!("  {:>8}  {}", bytes(&file["file_size"]), day(&file["created_at"]).unwrap_or_default()),
                        theme::dim(),
                    ),
                    Span::styled(if file["shared"].truthy() { "  🔗" } else { "" }, theme::dim()),
                ])),
            })
            .collect();
        self.selected = self.selected.min(items.len() - 1);
        let list = List::new(items).block(block).highlight_style(theme::selected());
        frame.render_stateful_widget(list, area, &mut ListState::default().with_selected(Some(self.selected)));
    }
}

fn file_icon(name: &str) -> &'static str {
    let extension = name.rsplit('.').next().unwrap_or("").to_lowercase();
    match extension.as_str() {
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "heic" => "🎨",
        "pdf" => "📕",
        "mp4" | "mov" | "webm" => "🎬",
        "mp3" | "wav" | "ogg" | "m4a" => "🎵",
        "zip" | "gz" | "tar" => "📦",
        "xls" | "xlsx" | "csv" | "numbers" => "📊",
        "ppt" | "pptx" | "key" => "📈",
        _ => "📄",
    }
}

/// Where a download goes: the current folder, without overwriting anything.
fn download_path(name: &str) -> PathBuf {
    let name = PathBuf::from(name).file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_else(|| "download".into());
    let path = PathBuf::from(&name);
    if !path.exists() {
        return path;
    }
    let (stem, extension) = match name.rsplit_once('.') {
        Some((stem, extension)) if !stem.is_empty() => (stem.to_string(), format!(".{extension}")),
        _ => (name.clone(), String::new()),
    };
    (1..).map(|number| PathBuf::from(format!("{stem} ({number}){extension}"))).find(|path| !path.exists()).unwrap()
}

fn file_detail(file: &Value) -> Detail {
    let mut lines = Vec::new();
    popups::field(&mut lines, "Type", file["content_type"].opt());
    popups::field(&mut lines, "Size", Some(bytes(&file["file_size"])));
    popups::field(&mut lines, "Added", Some(ago(&file["created_at"])).map(|at| format!("{at} by {}", file["creator"]["name"].s())));
    if file["shared"].truthy() {
        popups::field(&mut lines, "Shared", Some("with a public link 🔗".into()));
    }
    lines.push(Line::raw(""));
    lines.push(Line::from(Span::styled("Press esc, then d to download it here.", theme::dim())));
    Detail { title: file["name"].s(), lines, scroll: 0, url: file["url"].opt(), comment: None }
}

//! One screen per kind of tool, plus home. Each screen draws itself, handles
//! its own keys (returning false for keys the app should handle) and knows how
//! to reload its data without losing your place.

pub mod board;
pub mod calendar;
pub mod chat;
pub mod docs;
pub mod files;
pub mod home;
pub mod mail;
pub mod room;
pub mod todos;

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::Rect;
use serde_json::Value;

use super::app::{App, Fx, Job};
use crate::command::Result;
use crate::value::Json;

/// What screens may read from the app while drawing or handling a key.
pub struct View<'a> {
    pub tools: &'a [Value],
    pub tick: u64,
    pub me: &'a Value,
}

pub enum Screen {
    Home(home::Home),
    Board(board::Board),
    Todos(todos::Todos),
    Chat(chat::Chat),
    Docs(docs::Docs),
    Calendar(calendar::Calendar),
    Files(files::Files),
    Mail(mail::Mail),
    Room(room::Room),
}

/// Loads the screen for `tool`.
pub fn open(app: &mut App, tool: &Value) -> Result<Screen> {
    Ok(match tool["type"].s().as_str() {
        "boards" => Screen::Board(board::Board::load(app, tool.clone())?),
        "todos" => Screen::Todos(todos::Todos::load(app, tool.clone())?),
        "chat" => Screen::Chat(chat::Chat::load(app, tool.clone())?),
        "docs" => Screen::Docs(docs::Docs::load(app, tool.clone())?),
        "calendar" => Screen::Calendar(calendar::Calendar::load(app, tool.clone())?),
        "files" => Screen::Files(files::Files::load(app, tool.clone())?),
        "mail" => Screen::Mail(mail::Mail::load(app, tool.clone())?),
        _ => Screen::Room(room::Room { tool: tool.clone() }),
    })
}

/// After a tool opens from a link (a search result, a notification), shows
/// what the link points at: a card, todo, document, folder or conversation.
pub fn focus(app: &mut App, url: &str) -> Result<()> {
    let Some(tool) = app.screen.tool().map(|tool| tool["id"].int()) else { return Ok(()) };
    let number_after = |marker: &str| -> Option<i64> {
        let rest = url.split(marker).nth(1)?;
        rest.chars().take_while(char::is_ascii_digit).collect::<String>().parse().ok()
    };

    if let Some(card) = number_after("card=") {
        if let Screen::Board(board) = &mut app.screen {
            board.select(card);
        }
        app.popup = Some(super::popups::Popup::Detail(board::card_detail(app, tool, card)?));
    } else if let Some(item) = number_after("item=") {
        if let Screen::Todos(todos) = &mut app.screen {
            todos.select(item);
        }
        app.popup = Some(super::popups::Popup::Detail(todos::todo_detail(app, tool, item)?));
    } else if let Some(document) = number_after("/documents/") {
        let content = app.get(&format!("/tools/{tool}/docs/documents/{document}"), &[])?;
        if let Screen::Docs(docs) = &mut app.screen {
            docs.show(content);
        }
    } else if let Some(folder) = number_after("folder_id=") {
        if let Screen::Files(_) = app.screen {
            let tool = app.screen.tool().cloned().unwrap_or_default();
            app.screen = Screen::Files(files::Files::load_folder(app, tool, Some(folder))?);
        }
    } else if let Some(conversation) = number_after("/mails/") {
        app.popup = Some(super::popups::Popup::Detail(mail::conversation_detail(app, tool, conversation)?));
    }
    Ok(())
}

impl Screen {
    pub fn tool(&self) -> Option<&Value> {
        match self {
            Screen::Home(_) => None,
            Screen::Board(screen) => Some(&screen.tool),
            Screen::Todos(screen) => Some(&screen.tool),
            Screen::Chat(screen) => Some(&screen.tool),
            Screen::Docs(screen) => Some(&screen.tool),
            Screen::Calendar(screen) => Some(&screen.tool),
            Screen::Files(screen) => Some(&screen.tool),
            Screen::Mail(screen) => Some(&screen.tool),
            Screen::Room(screen) => Some(&screen.tool),
        }
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect, view: &View) {
        match self {
            Screen::Home(screen) => screen.draw(frame, area, view),
            Screen::Board(screen) => screen.draw(frame, area),
            Screen::Todos(screen) => screen.draw(frame, area),
            Screen::Chat(screen) => screen.draw(frame, area),
            Screen::Docs(screen) => screen.draw(frame, area),
            Screen::Calendar(screen) => screen.draw(frame, area),
            Screen::Files(screen) => screen.draw(frame, area),
            Screen::Mail(screen) => screen.draw(frame, area),
            Screen::Room(screen) => screen.draw(frame, area),
        }
    }

    /// Returns false when the key is left to the app.
    pub fn key(&mut self, key: KeyEvent, view: &View, fx: &mut Fx) -> bool {
        match self {
            Screen::Home(screen) => screen.key(key, view, fx),
            Screen::Board(screen) => screen.key(key, fx),
            Screen::Todos(screen) => screen.key(key, fx),
            Screen::Chat(screen) => screen.key(key, fx),
            Screen::Docs(screen) => screen.key(key, fx),
            Screen::Calendar(screen) => screen.key(key, fx),
            Screen::Files(screen) => screen.key(key, fx),
            Screen::Mail(screen) => screen.key(key, fx),
            Screen::Room(_) => false,
        }
    }

    /// Reloads the screen's data, keeping the selection.
    pub fn refresh(&self) -> Option<Job> {
        match self {
            Screen::Home(_) => None,
            Screen::Board(screen) => Some(screen.refresh()),
            Screen::Todos(screen) => Some(screen.refresh()),
            Screen::Chat(screen) => Some(screen.refresh()),
            Screen::Docs(screen) => Some(screen.refresh()),
            Screen::Calendar(screen) => Some(screen.refresh()),
            Screen::Files(screen) => Some(screen.refresh()),
            Screen::Mail(screen) => Some(screen.refresh()),
            Screen::Room(_) => None,
        }
    }

    /// What a screen that changes while you look at it reloads every few seconds, in the background.
    pub fn live_request(&self) -> Option<(String, Vec<(&'static str, String)>)> {
        match self {
            Screen::Home(_) => Some(("/notifications".into(), vec![("limit", home::NOTIFICATIONS.to_string())])),
            Screen::Board(screen) => Some((format!("/tools/{}/board", screen.tool["id"].s()), vec![])),
            Screen::Todos(screen) => Some((format!("/tools/{}/todo", screen.tool["id"].s()), vec![])),
            Screen::Chat(screen) => Some((format!("/tools/{}/chat", screen.tool["id"].s()), vec![("limit", chat::PAGE.to_string())])),
            _ => None,
        }
    }

    /// Takes in what `live_request` fetched, keeping your place.
    pub fn apply_live(&mut self, value: Value) {
        match self {
            Screen::Home(screen) => screen.replace_notifications(value.items().to_vec()),
            Screen::Board(screen) => screen.replace(value["columns"].items().to_vec(), None),
            Screen::Todos(screen) => screen.replace(value["lists"].items().to_vec(), None),
            Screen::Chat(screen) => screen.merge(value),
            _ => {}
        }
    }

    pub fn hints(&self) -> Vec<(&'static str, &'static str)> {
        match self {
            Screen::Home(_) => vec![("↑↓", "choose"), ("enter", "open"), ("/", "search"), ("n", "notifications"), ("q", "quit")],
            Screen::Board(_) => board::HINTS.to_vec(),
            Screen::Todos(_) => todos::HINTS.to_vec(),
            Screen::Chat(screen) => screen.hints(),
            Screen::Docs(_) => docs::HINTS.to_vec(),
            Screen::Calendar(_) => calendar::HINTS.to_vec(),
            Screen::Files(_) => files::HINTS.to_vec(),
            Screen::Mail(_) => mail::HINTS.to_vec(),
            Screen::Room(_) => vec![("o", "open in browser"), ("esc", "home")],
        }
    }

    /// The keys of this screen, for the help popup.
    pub fn help(&self) -> Vec<(&'static str, &'static str)> {
        match self {
            Screen::Home(_) => home::HELP.to_vec(),
            Screen::Board(_) => board::HELP.to_vec(),
            Screen::Todos(_) => todos::HELP.to_vec(),
            Screen::Chat(_) => chat::HELP.to_vec(),
            Screen::Docs(_) => docs::HELP.to_vec(),
            Screen::Calendar(_) => calendar::HELP.to_vec(),
            Screen::Files(_) => files::HELP.to_vec(),
            Screen::Mail(_) => mail::HELP.to_vec(),
            Screen::Room(_) => vec![("o", "Open the room in your browser")],
        }
    }
}

/// Moves a selection up or down a list of `count` items; true when the key was a move.
pub fn move_selection(selected: &mut usize, count: usize, key: KeyEvent) -> bool {
    let last = count.saturating_sub(1);
    match key.code {
        KeyCode::Down | KeyCode::Char('j') => *selected = (*selected + 1).min(last),
        KeyCode::Up | KeyCode::Char('k') => *selected = selected.saturating_sub(1),
        KeyCode::PageDown => *selected = (*selected + 10).min(last),
        KeyCode::PageUp => *selected = selected.saturating_sub(10),
        KeyCode::Home => *selected = 0,
        KeyCode::End | KeyCode::Char('G') => *selected = last,
        _ => return false,
    }
    true
}

//! The app against a fake server, drawn on a virtual terminal and driven by key presses.

use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;

use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use serde_json::{Value, json};

use super::app::App;
use crate::client::{Api, Method};
use crate::command::Result;

type Calls = Rc<RefCell<Vec<(Method, String, Value)>>>;

/// Answers from a map of paths (and records every request).
struct FakeServer {
    responses: Value,
    calls: Calls,
}

impl Api for FakeServer {
    fn request(&mut self, method: Method, path: &str, _params: &[(&str, String)], body: &Value) -> Result<Value> {
        self.calls.borrow_mut().push((method, path.to_string(), body.clone()));
        let key = if method == Method::Get { path.to_string() } else { format!("{method:?} {path}") };
        Ok(self.responses.get(&key).cloned().unwrap_or(json!({})))
    }

    fn upload(&mut self, _path: &str, _files: &[(&str, &str)], _fields: &[(&str, String)]) -> Result<Value> {
        unreachable!()
    }

    fn download(&mut self, _path: &str, _destination: &Path) -> Result<Option<String>> {
        unreachable!()
    }
}

fn card(id: i64, title: &str) -> Value {
    json!({ "id": id, "title": title, "color": "", "comments_count": 0, "attachments_count": 0 })
}

fn server() -> Value {
    json!({
        "/profile": { "id": 1, "name": "Sem Goedknegt", "email_address": "sem@example.com" },
        "/tools": [
            { "id": 10, "name": "Launch", "type": "boards", "unread": true },
            { "id": 11, "name": "Chores", "type": "todos" },
            { "id": 12, "name": "Team", "type": "chat" }
        ],
        "/notifications": [
            { "id": 5, "read": false, "message": "Ann commented on Fix login", "url": "/tools/10/board?card=101", "created_at": "2026-09-24T10:00:00Z" }
        ],
        "/tools/10/board": { "columns": [
            { "id": 1, "name": "To Do", "cards": [card(101, "Fix login"), card(102, "Write post")] },
            { "id": 2, "name": "Done", "cards": [] }
        ] },
        "/tools/10/board/cards/101": { "id": 101, "title": "Fix login", "description": "Safari logs people out.",
            "column": { "name": "To Do" }, "comments": [{ "user": { "name": "Ann" }, "body": "Found it!", "created_at": "2026-09-24T10:00:00Z" }],
            "attachments": [] },
        "/tools/11/todo": { "lists": [{ "id": 7, "title": "Home", "items": [{ "id": 70, "title": "Water plants", "completed": false }] }] },
        "/tools/12/chat": { "messages": [
            { "id": 1, "user": { "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z", "reactions": [] }
        ] },
        "/search": { "results": [{ "kind": "card", "title": "Fix login", "tool_name": "Launch", "url": "http://localhost/tools/10/board?card=101" }] },
        "Post /columns/1/cards": { "id": 103, "title": "Ship it" }
    })
}

struct Harness {
    app: App,
    terminal: Terminal<TestBackend>,
    calls: Calls,
}

impl Harness {
    fn new() -> Self {
        let calls = Calls::default();
        let mut app = App::new(Box::new(FakeServer { responses: server(), calls: calls.clone() }), "http://localhost".into());
        app.launch_browser = false;
        app.start().unwrap();
        let terminal = Terminal::new(TestBackend::new(100, 30)).unwrap();
        Self { app, terminal, calls }
    }

    fn press(&mut self, code: KeyCode) -> &mut Self {
        self.app.key(KeyEvent::new(code, KeyModifiers::NONE));
        self.app.settle();
        self
    }

    fn typing(&mut self, text: &str) -> &mut Self {
        for char in text.chars() {
            self.press(KeyCode::Char(char));
        }
        self
    }

    fn screen(&mut self) -> String {
        self.terminal.draw(|frame| self.app.draw(frame)).unwrap();
        let buffer = self.terminal.backend().buffer();
        (0..buffer.area.height)
            .map(|y| (0..buffer.area.width).map(|x| buffer[(x, y)].symbol().to_string()).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn sent(&self, method: Method, path: &str) -> Option<Value> {
        self.calls.borrow().iter().rev().find(|(m, p, _)| *m == method && p == path).map(|(_, _, body)| body.clone())
    }
}

#[test]
fn home_greets_and_lists_the_tools() {
    let mut harness = Harness::new();
    let screen = harness.screen();

    assert!(screen.contains("Sem"), "{screen}");
    assert!(screen.contains("Launch") && screen.contains("Chores") && screen.contains("Team"));
    assert!(screen.contains("Ann commented on Fix login"));
    assert!(screen.contains("1 new notification"));
}

#[test]
fn a_board_shows_columns_and_opens_a_card() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2'));
    let screen = harness.screen();
    assert!(screen.contains("To Do 2") && screen.contains("Done 0") && screen.contains("Write post"), "{screen}");

    harness.press(KeyCode::Enter);
    let screen = harness.screen();
    assert!(screen.contains("Safari logs people out.") && screen.contains("Found it!"), "{screen}");
}

#[test]
fn moving_a_card_to_done_saves_it_and_celebrates() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Char('L'));

    assert_eq!(harness.sent(Method::Patch, "/tools/10/board/cards/101/position"), Some(json!({ "column_id": 2 })));
}

#[test]
fn a_new_card_goes_to_the_selected_column() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Char('c')).typing("Ship it").press(KeyCode::Enter);

    assert_eq!(harness.sent(Method::Post, "/columns/1/cards"), Some(json!({ "card": { "title": "Ship it" } })));
}

#[test]
fn space_ticks_a_todo_off() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('1')).press(KeyCode::Char(' '));

    assert!(harness.sent(Method::Post, "/tools/11/todo/items/70/completion").is_some());
}

#[test]
fn a_chat_message_is_sent_as_a_paragraph() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('3'));
    assert!(harness.screen().contains("Morning!"));

    harness.press(KeyCode::Char('i')).typing("Hi <all>").press(KeyCode::Enter);
    assert_eq!(harness.sent(Method::Post, "/tools/12/chat/messages"), Some(json!({ "message": { "body": "<p>Hi &lt;all&gt;</p>" } })));
}

#[test]
fn keys_typed_while_writing_are_text_not_commands() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('3')).press(KeyCode::Char('i')).typing("q/?n");

    assert!(!harness.app.quit);
    assert!(harness.app.popup.is_none());
    assert!(harness.screen().contains("q/?n"));
}

#[test]
fn a_search_result_opens_the_card_it_found() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('/')).typing("login").press(KeyCode::Enter);
    assert!(harness.screen().contains("Fix login"));

    harness.press(KeyCode::Enter);
    let screen = harness.screen();
    assert!(screen.lines().next().unwrap().contains("Launch"), "{screen}");
    assert!(screen.contains("Safari logs people out."), "{screen}");
}

#[test]
fn escape_goes_home_and_q_quits() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Esc);
    assert!(harness.screen().contains("Your tools"));

    harness.press(KeyCode::Char('q'));
    assert!(harness.app.quit);
}

#[test]
fn o_opens_the_card_in_the_browser() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Char('o'));

    assert_eq!(harness.app.opened, vec!["http://localhost/tools/10/board?card=101".to_string()]);
}

#[test]
fn a_tiny_terminal_asks_for_room() {
    let mut harness = Harness::new();
    harness.terminal = Terminal::new(TestBackend::new(40, 10)).unwrap();

    assert!(harness.screen().contains("bigger"));
}

#[test]
fn u_undoes_a_move() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Char('L'));
    assert!(harness.screen().contains("u undo"));

    harness.press(KeyCode::Char('u'));
    assert_eq!(harness.sent(Method::Patch, "/tools/10/board/cards/101/position"), Some(json!({ "column_id": 1, "position": 0 })));
    assert!(!harness.screen().contains("u undo"));
}

#[test]
fn e_renames_a_card_starting_from_its_title() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Char('e'));
    assert!(harness.screen().contains("Fix login"));

    harness.press(KeyCode::Backspace).typing("ns").press(KeyCode::Enter);
    assert_eq!(harness.sent(Method::Patch, "/tools/10/board/cards/101"), Some(json!({ "card": { "title": "Fix logins" } })));
}

#[test]
fn d_sets_a_due_date_in_words() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Char('d')).typing("tomorrow").press(KeyCode::Enter);

    let tomorrow = crate::command::today().tomorrow().unwrap().to_string();
    assert_eq!(harness.sent(Method::Patch, "/tools/10/board/cards/101"), Some(json!({ "card": { "due_date": tomorrow } })));
}

#[test]
fn due_dates_read_like_people_write_them() {
    use super::widgets::due_date;
    let today = crate::command::today();

    assert_eq!(due_date("none"), Ok(None));
    assert_eq!(due_date("+3"), Ok(Some(today.checked_add(jiff::Span::new().days(3)).unwrap())));
    assert_eq!(due_date("2026-10-01"), Ok(Some(jiff::civil::date(2026, 10, 1))));
    let friday = due_date("fri").unwrap().unwrap();
    assert_eq!(friday.weekday(), jiff::civil::Weekday::Friday);
    assert!(friday > today && friday <= today.checked_add(jiff::Span::new().days(7)).unwrap());
    assert!(due_date("someday").is_err());
}

#[test]
fn a_refresh_keeps_the_selected_card_when_cards_move() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('2')).press(KeyCode::Down);
    let super::screens::Screen::Board(board) = &mut harness.app.screen else { panic!("not on the board") };

    // Someone else put a card above it.
    board.replace(
        vec![
            json!({ "id": 1, "name": "To Do", "cards": [card(100, "New one"), card(101, "Fix login"), card(102, "Write post")] }),
            json!({ "id": 2, "name": "Done", "cards": [] }),
        ],
        None,
    );
    harness.press(KeyCode::Enter);
    assert!(harness.calls.borrow().iter().any(|(_, path, _)| path == "/tools/10/board/cards/102"));
}

#[test]
fn new_chat_messages_join_the_ones_already_loaded() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Char('3'));
    let super::screens::Screen::Chat(chat) = &mut harness.app.screen else { panic!("not in the chat") };

    chat.merge(json!({ "messages": [
        { "id": 1, "user": { "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z", "reactions": [] },
        { "id": 2, "user": { "name": "Bo" }, "body": "Hey Ann", "created_at": "2026-09-24T08:01:00Z", "reactions": [] }
    ] }));
    let screen = harness.screen();
    assert!(screen.contains("Morning!") && screen.contains("Hey Ann"), "{screen}");
}

#[test]
fn opening_a_notification_marks_it_read() {
    let mut harness = Harness::new();
    harness.press(KeyCode::Tab).press(KeyCode::Enter);

    assert!(harness.sent(Method::Post, "/notifications/5/read").is_some());
    assert!(harness.screen().contains("Safari logs people out."));
}

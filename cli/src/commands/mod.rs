//! Every command, by noun. `dobase help` lists them in this order within a noun.

mod account;
mod boards;
mod calendar;
mod chat;
mod docs;
mod files;
mod mail;
mod notifications;
mod search;
mod todos;
mod tools;

use crate::command::Definition;

pub fn definitions() -> Vec<Definition> {
    [
        account::definitions(),
        boards::definitions(),
        calendar::definitions(),
        chat::definitions(),
        docs::definitions(),
        files::definitions(),
        mail::definitions(),
        notifications::definitions(),
        search::definitions(),
        todos::definitions(),
        tools::definitions(),
    ]
    .into_iter()
    .flatten()
    .collect()
}

/// What each noun is, shown in `dobase help`.
pub fn nouns() -> Vec<(&'static str, &'static str)> {
    vec![
        ("card", "Cards on a board (boards tools)"),
        ("column", "Columns on a board (boards tools)"),
        ("event", "Events in a calendar (calendar tools)"),
        ("calendar", "The calendars of a calendar tool, and syncing them"),
        ("chat", "Messages in a chat (chat tools)"),
        ("doc", "Documents (docs tools)"),
        ("file", "Files and their downloads (files tools)"),
        ("folder", "Folders of files (files tools)"),
        ("mail", "Email in mail tools: conversations, flags, drafts and sending"),
        ("notification", "Your notifications"),
        ("search", "Search every tool you share"),
        ("todo", "Todos on lists (todos tools)"),
        ("todolist", "Lists in a todos tool"),
        ("tool", "The tools you have access to"),
    ]
}

//! Tests that need no server: the commands and their help, argument parsing,
//! the input helpers commands rely on, and one command against a fake API.

use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;

use serde_json::{Value, json};

use crate::cli;
use crate::client::{Api, Method};
use crate::command::{Ctx, Error, Result, clean, date_param, paragraphs, today};
use crate::commands;
use crate::config::Config;

fn run(args: &[&str]) -> (i32, String, String) {
    let (mut out, mut err) = (Vec::new(), Vec::new());
    let status = cli::run(args.iter().map(|arg| arg.to_string()).collect(), &mut out, &mut err);
    (status, String::from_utf8(out).unwrap(), String::from_utf8(err).unwrap())
}

#[test]
fn help_lists_every_command() {
    let (status, out, _) = run(&["help"]);

    assert_eq!(status, 0);
    for definition in commands::definitions() {
        assert!(out.contains(&format!("dobase {}", definition.name)), "help misses {}", definition.name);
    }
}

#[test]
fn noun_help_shows_flags() {
    let (status, out, _) = run(&["help", "card"]);

    assert_eq!(status, 0);
    assert!(out.contains("--assignee USER"));
}

#[test]
fn command_help_shows_usage() {
    let (status, out, _) = run(&["card", "create", "--help"]);

    assert_eq!(status, 0);
    assert!(out.starts_with("Usage: dobase card create TOOL TITLE"));
}

#[test]
fn unknown_commands_exit_with_a_usage_error() {
    let (status, _, err) = run(&["frobnicate"]);

    assert_eq!(status, 2);
    assert!(err.contains("Unknown command"));
}

#[test]
fn wrong_arguments_exit_with_a_usage_error() {
    let (status, _, err) = run(&["card", "create", "board"]);
    assert_eq!(status, 2);
    assert!(err.starts_with("Usage: dobase card create TOOL TITLE"));

    let (status, _, err) = run(&["card", "create", "board", "title", "--bogus"]);
    assert_eq!(status, 2);
    assert!(err.starts_with("invalid option: --bogus"));

    let (status, _, err) = run(&["card", "create", "board", "title", "--due"]);
    assert_eq!(status, 2);
    assert!(err.starts_with("missing argument: --due"));
}

#[test]
fn every_command_has_a_summary_and_well_formed_arguments() {
    let nouns = commands::nouns();
    for definition in commands::definitions() {
        assert!(!definition.summary.is_empty(), "{} has no summary", definition.name);
        for arg in &definition.args {
            let bare = arg.trim_start_matches('[').trim_end_matches(']').trim_end_matches("...");
            assert!(bare.chars().all(|char| char.is_ascii_uppercase() || char == '/'), "{} has odd args: {arg}", definition.name);
        }
        if let Some(noun) = definition.noun() {
            assert!(nouns.iter().any(|(name, _)| *name == noun), "{} has no noun summary", definition.name);
        }
    }
}

#[test]
fn the_skill_and_readmes_only_show_commands_and_flags_that_exist() {
    let definitions = commands::definitions();
    let documents = [
        ("cli/SKILL.md", include_str!("../SKILL.md"), "dobase "),
        ("cli/README.md", include_str!("../README.md"), "dobase "),
        ("README.md", include_str!("../../README.md"), "dobase "),
    ];

    let mut examples = 0;
    for (file, contents, prefix) in documents {
        for line in contents.lines().filter_map(|line| line.strip_prefix(prefix)) {
            let line = line.split(" #").next().unwrap().trim_end();
            let line = line.split(" <<'").next().unwrap();
            let words = shell_words(line);
            if words.first().is_none_or(|word| word == "help" || word.starts_with('-')) {
                continue;
            }
            examples += 1;

            let name = words.iter().take(2).cloned().collect::<Vec<_>>().join(" ");
            let definition = definitions
                .iter()
                .find(|definition| definition.name == name)
                .or_else(|| definitions.iter().find(|definition| definition.name == words[0]));
            let Some(definition) = definition else { panic!("{file}: unknown command in `{line}`") };

            for flag in words.iter().filter_map(|word| word.strip_prefix("--")).filter(|flag| !flag.is_empty()) {
                let flag = flag.split('=').next().unwrap();
                assert!(
                    flag == "json" || definition.flags.iter().any(|known| known.name == flag),
                    "{file}: `{}` has no --{flag} (in `{line}`)",
                    definition.name
                );
            }
        }
    }
    assert!(examples > 20, "only {examples} examples found");
}

#[test]
fn printed_text_loses_control_characters_but_keeps_newlines_and_tabs() {
    assert_eq!(clean("Hi \x1b]52;c;cHduZWQ=\x07\x1b[2Jthere\n\ttabbed\u{9b}"), "Hi ]52;c;cHduZWQ=[2Jthere\n\ttabbed");
}

#[test]
fn plain_text_becomes_escaped_paragraphs() {
    assert_eq!(
        paragraphs("Hello <b>you</b>\nsecond line\n\n\nNew paragraph\n"),
        "<p>Hello &lt;b&gt;you&lt;/b&gt;<br>second line</p><p>New paragraph</p>"
    );
}

#[test]
fn dates_accept_keywords_and_iso_dates_only() {
    assert_eq!(date_param("none").unwrap(), None);
    assert_eq!(date_param("today").unwrap(), Some(today().to_string()));
    assert_eq!(date_param("2026-10-01").unwrap(), Some("2026-10-01".to_string()));
    assert!(matches!(date_param("friday"), Err(Error::Usage(_))));
    assert!(matches!(date_param("2026-02-30"), Err(Error::Usage(_))));
}

#[test]
fn tool_and_id_references_must_end_in_a_numeric_id() {
    let mut out = Vec::new();
    let mut ctx = Ctx::new(Config::default(), &mut out, false, "test".into());

    assert!(matches!(ctx.tool_and_id("104", "boards", "card"), Err(Error::Usage(_))));
    assert!(matches!(ctx.tool_and_id("roadmap/abc", "boards", "card"), Err(Error::Usage(_))));
}

/// Answers GETs from a fixed set of paths, records every POST body and the paths
/// it posted or downloaded from, and saves downloads as "data from PATH".
struct FakeApi {
    responses: Value,
    sent: Rc<RefCell<Vec<Value>>>,
    paths: Rc<RefCell<Vec<String>>>,
}

impl FakeApi {
    fn new(responses: Value, sent: &Rc<RefCell<Vec<Value>>>) -> Self {
        Self { responses, sent: sent.clone(), paths: Rc::default() }
    }
}

impl Api for FakeApi {
    fn request(&mut self, method: Method, path: &str, _params: &[(&str, String)], body: &Value) -> Result<Value> {
        match method {
            Method::Get => Ok(self.responses[path].clone()),
            _ => {
                self.sent.borrow_mut().push(body.clone());
                self.paths.borrow_mut().push(path.to_string());
                Ok(json!({ "id": 400, "subject": body["subject"], "to": ["ann@example.com"], "cc": [],
                           "url": "https://dobase.test/tools/8/mails/new?draft_id=400" }))
            }
        }
    }

    fn upload(&mut self, _path: &str, _files: &[(&str, &str)], _fields: &[(&str, String)]) -> Result<Value> {
        unreachable!()
    }

    fn download(&mut self, path: &str, destination: &Path) -> Result<Option<String>> {
        self.paths.borrow_mut().push(path.to_string());
        std::fs::write(destination, format!("data from {path}")).unwrap();
        Ok(None)
    }
}

fn invoke(ctx: &mut Ctx, name: &str, argv: &[&str]) -> Result<()> {
    let definitions = commands::definitions();
    let definition = definitions.iter().find(|definition| definition.name == name).unwrap();
    let args = definition.parse(&argv.iter().map(|arg| arg.to_string()).collect::<Vec<_>>())?;
    (definition.run)(ctx, &args)
}

#[test]
fn replies_sent_from_the_cli_name_the_message_they_answer() {
    let sent = Rc::new(RefCell::new(Vec::new()));
    let responses = json!({
        "/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
        "/tools/8/mails/310": { "account": { "email_address": "me@example.com" }, "messages": [
            { "id": 310, "draft": false, "from_address": "ann@example.com", "to": ["me@example.com", "bob@example.com"],
              "cc": ["ANN@example.com", "cy@example.com"], "subject": "Re: Plans", "message_id": "plans@example.com" }
        ] },
        "/tools/8/mails/311": { "messages": [
            { "id": 311, "draft": false, "subject": "Scans", "attachments": [
                { "id": 71, "filename": "../../scan.pdf", "file_size": 1, "download_url": "https://dobase.test/blobs/71" },
                { "id": 72, "filename": "scan.pdf", "file_size": 1, "download_url": "https://dobase.test/blobs/72" },
                { "id": 73, "filename": "..", "file_size": 1, "download_url": "https://dobase.test/blobs/73" }
            ] }
        ] },
        "/tools/8/mails/312": { "messages": [
            { "id": 312, "draft": true, "to": ["ann@example.com"], "cc": [], "subject": "Re: Plans",
              "body_html": "<p>Yes</p>", "in_reply_to": "plans@example.com" }
        ] }
    });
    let mut out = Vec::new();
    let mut ctx = Ctx::new(Config::default(), &mut out, false, "test".into());
    ctx.set_api(Box::new(FakeApi::new(responses, &sent)));

    invoke(&mut ctx, "mail reply", &["8/310", "--body", "Sure", "--send", "--all"]).unwrap();
    invoke(&mut ctx, "mail send", &["8", "--draft", "312"]).unwrap();

    let sent = sent.borrow();
    assert_eq!(sent.iter().map(|email| email["in_reply_to"].clone()).collect::<Vec<_>>(), vec![json!("plans@example.com"); 2]);
    assert_eq!(sent[0]["to"], "ann@example.com");
    assert_eq!(sent[0]["cc"], "bob@example.com, cy@example.com");
    assert_eq!(sent[0]["subject"], "Re: Plans");
    assert_eq!(sent[0]["body"], "<p>Sure</p>");
    assert_eq!(sent[1]["draft_id"], 312);
    drop(sent);
    drop(ctx);
    assert!(String::from_utf8(out).unwrap().contains("Sent \"Re: Plans\" to ann@example.com."));
}

fn mail_with_attachments() -> Value {
    json!({
        "/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
        "/tools/8/mails/310": { "account": { "email_address": "me@example.com" }, "messages": [
            { "id": 310, "draft": false, "from_name": "Ann <Lee>", "from_address": "ann@example.com", "to": ["me@example.com"],
              "cc": [], "subject": "Re: Plans", "sent_at": "2026-09-24T14:05:00.000+02:00", "body": "Plan A & B\n\nOK?", "body_html": null,
              "attachments": [
                { "id": 51, "filename": "plan.pdf", "file_size": 2048, "download_url": "https://dobase.test/blobs/51/plan.pdf" },
                { "id": 52, "filename": "../plan.pdf", "file_size": 10, "download_url": "https://dobase.test/blobs/52/plan.pdf" },
                { "id": 53, "filename": "huge.mov", "file_size": 99, "download_url": null }
              ] }
        ] },
        "/tools/8/mails/311": { "messages": [
            { "id": 311, "draft": false, "subject": "Scans", "attachments": [
                { "id": 71, "filename": "../../scan.pdf", "file_size": 1, "download_url": "https://dobase.test/blobs/71" },
                { "id": 72, "filename": "scan.pdf", "file_size": 1, "download_url": "https://dobase.test/blobs/72" },
                { "id": 73, "filename": "..", "file_size": 1, "download_url": "https://dobase.test/blobs/73" }
            ] }
        ] },
        "/tools/8/mails/312": { "messages": [
            { "id": 312, "draft": true, "to": ["bob@example.com"], "cc": [], "subject": "Fwd: Plans", "body_html": "<p>FYI</p>",
              "in_reply_to": null, "attachments": [{ "id": 61, "filename": "plan.pdf", "file_size": 2048, "download_url": "https://dobase.test/blobs/61" }] }
        ] }
    })
}

fn mail_ctx<'a>(out: &'a mut Vec<u8>, json: bool, api: FakeApi, opened: &Rc<RefCell<Vec<String>>>) -> Ctx<'a> {
    let mut ctx = Ctx::new(Config::default(), out, json, "test".into());
    ctx.set_api(Box::new(api));
    let opened = opened.clone();
    ctx.browser = Box::new(move |url| {
        opened.borrow_mut().push(url.to_string());
        Ok(())
    });
    ctx
}

#[test]
fn forwards_quote_the_original_and_carry_its_stored_attachments() {
    let sent = Rc::new(RefCell::new(Vec::new()));
    let opened = Rc::new(RefCell::new(Vec::new()));
    let api = FakeApi::new(mail_with_attachments(), &sent);
    let paths = api.paths.clone();
    let mut out = Vec::new();
    let mut ctx = mail_ctx(&mut out, false, api, &opened);

    invoke(&mut ctx, "mail forward", &["8/310", "--to", "bob@example.com", "--body", "See below", "--open"]).unwrap();
    invoke(&mut ctx, "mail send", &["8", "--draft", "312"]).unwrap();

    let sent = sent.borrow();
    assert_eq!(*paths.borrow(), vec!["/tools/8/mails/drafts", "/tools/8/mails"]);
    assert_eq!(sent[0]["to"], "bob@example.com");
    assert_eq!(sent[0]["subject"], "Fwd: Plans");
    assert_eq!(sent[0]["forward_attachment_ids"], json!([51, 52]));
    assert_eq!(
        sent[0]["body"],
        "<p>See below</p><br><br><p>---------- Forwarded message ----------<br>From: Ann &lt;Lee&gt; &lt;ann@example.com&gt;<br>\
         Date: 2026-09-24 14:05<br>Subject: Re: Plans<br>To: me@example.com</p><p>Plan A &amp; B</p><p>OK?</p>"
    );
    assert_eq!(*opened.borrow(), vec!["https://dobase.test/tools/8/mails/new?draft_id=400"]);
    assert_eq!(sent[1]["forward_attachment_ids"], json!([61]));
    drop(sent);
    drop(ctx);
    assert!(String::from_utf8(out).unwrap().contains("Saved forward draft 8/400 \"Fwd: Plans\" to ann@example.com with 2 attachments."));
}

#[test]
fn open_is_only_for_drafts() {
    let (status, _, err) = run(&["mail", "forward", "8/310", "--to", "a@example.com", "--send", "--open"]);
    assert_eq!(status, 2);
    assert!(err.contains("--open opens a saved draft"));

    let (status, _, err) = run(&["mail", "reply", "8/310", "--body", "Hi", "--send", "--open"]);
    assert_eq!(status, 2);
    assert!(err.contains("--open opens a saved draft"));
}

#[test]
fn attachments_are_listed_and_saved_under_their_own_names() {
    let directory = std::env::temp_dir().join(format!("dobase-attachments-{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let sent = Rc::new(RefCell::new(Vec::new()));
    let opened = Rc::new(RefCell::new(Vec::new()));

    let mut out = Vec::new();
    let mut ctx = mail_ctx(&mut out, true, FakeApi::new(mail_with_attachments(), &sent), &opened);
    invoke(&mut ctx, "mail attachments", &["8/310"]).unwrap();
    drop(ctx);
    let listed: Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(listed.as_array().unwrap().len(), 3);

    // huge.mov was never stored, so saving everything fails before anything is downloaded
    let mut out = Vec::new();
    let api = FakeApi::new(mail_with_attachments(), &sent);
    let paths = api.paths.clone();
    let mut ctx = mail_ctx(&mut out, false, api, &opened);
    let save = directory.to_str().unwrap();
    assert!(matches!(invoke(&mut ctx, "mail attachments", &["8/310", "--save", save]), Err(Error::Failed(_))));
    assert!(paths.borrow().is_empty());

    invoke(&mut ctx, "mail attachments", &["8/310", "--save", save, "--name", "PLAN.PDF"]).unwrap();
    assert_eq!(std::fs::read_to_string(directory.join("plan.pdf")).unwrap(), "data from https://dobase.test/blobs/51/plan.pdf");
    assert!(matches!(invoke(&mut ctx, "mail attachments", &["8/310", "--save", save, "--name", "plan.pdf"]), Err(Error::Failed(_))));
    assert!(matches!(invoke(&mut ctx, "mail attachments", &["8/310", "--name", "nope.txt"]), Err(Error::Failed(_))));

    // Names from the mail stay inside the directory, and the same name twice gets a number
    invoke(&mut ctx, "mail attachments", &["8/311", "--save", save]).unwrap();
    for (name, blob) in [("scan.pdf", 71), ("scan (2).pdf", 72), ("attachment", 73)] {
        assert_eq!(std::fs::read_to_string(directory.join(name)).unwrap(), format!("data from https://dobase.test/blobs/{blob}"));
    }
    drop(ctx);
    assert!(String::from_utf8(out).unwrap().contains(&format!("Saved plan.pdf (2.0 KB) to {save}/plan.pdf.")));
    std::fs::remove_dir_all(&directory).unwrap();
}

/// Splits a command line like a shell: spaces separate words, quotes group them.
fn shell_words(line: &str) -> Vec<String> {
    let (mut words, mut word, mut quote, mut started) = (Vec::new(), String::new(), None, false);
    for char in line.chars() {
        match (quote, char) {
            (None, '"' | '\'') => {
                quote = Some(char);
                started = true;
            }
            (Some(open), _) if char == open => quote = None,
            (None, ' ') => {
                if started {
                    words.push(std::mem::take(&mut word));
                    started = false;
                }
            }
            _ => {
                word.push(char);
                started = true;
            }
        }
    }
    if started {
        words.push(word);
    }
    words
}

use serde_json::{Value, json};

use crate::command::{Args, Ctx, Definition, Error, Result, bytes, command, count, escape_html, fail, flag, moment, quoted, switch, usage};
use crate::value::{Json, is_digits, join};

const VIEWS: [(&str, &str); 6] =
    [("inbox", "Inbox"), ("drafts", "Drafts"), ("starred", "Starred"), ("sent", "Sent"), ("archive", "Archive"), ("trash", "Trash")];

const TO: &str = "Recipients, comma-separated";
const CC: &str = "Cc recipients, comma-separated";
const BODY: &str = "Message (plain text, or HTML with --html)";

pub fn definitions() -> Vec<Definition> {
    let views: Vec<&str> = VIEWS.iter().map(|(view, _)| *view).collect();
    vec![
        command(
            "mail list",
            "List the conversations in a folder (inbox unless --folder)",
            &["TOOL"],
            vec![
                flag("folder", "FOLDER", format!("{} or a custom folder", views.join(", "))),
                flag("search", "QUERY", "Only conversations whose subject, sender or text matches"),
                flag("page", "N", "Page (30 conversations per page)"),
            ],
            list,
        ),
        command(
            "mail show",
            "Show a conversation: every message in it, oldest first",
            &["TOOL/MESSAGE"],
            vec![switch("html", "Print the HTML of each message instead of its text")],
            show,
        ),
        command("mail read", "Mark a message as read, here and on the mail server", &["TOOL/MESSAGE"], vec![], read),
        command("mail unread", "Mark a message as unread, here and on the mail server", &["TOOL/MESSAGE"], vec![], unread),
        command("mail star", "Star a message (flagged on the mail server)", &["TOOL/MESSAGE"], vec![], star),
        command("mail unstar", "Remove the star from a message", &["TOOL/MESSAGE"], vec![], unstar),
        command(
            "mail archive",
            "Archive a message (moved to the account's archive folder on the server, if it has one)",
            &["TOOL/MESSAGE"],
            vec![],
            archive,
        ),
        command("mail unarchive", "Move an archived message back to the inbox", &["TOOL/MESSAGE"], vec![], unarchive),
        command(
            "mail move",
            "Move a message to another folder on the mail server: INBOX, Sent or a custom folder",
            &["TOOL/MESSAGE", "FOLDER"],
            vec![],
            move_message,
        ),
        command(
            "mail draft",
            "Save a new draft (nothing is sent; it is copied to the server's Drafts folder)",
            &["TOOL"],
            vec![
                flag("to", "ADDRS", TO),
                flag("cc", "ADDRS", CC),
                flag("subject", "TEXT", "Subject"),
                flag("body", "TEXT", BODY),
                switch("html", "The body is HTML"),
            ],
            draft,
        ),
        command(
            "mail reply",
            "Reply to a message: saves a draft, or sends real email right away with --send",
            &["TOOL/MESSAGE"],
            vec![
                flag("body", "TEXT", "Your reply (plain text, or HTML with --html)"),
                switch("all", "Reply to all: cc everyone else on the message"),
                switch("html", "The body is HTML"),
                switch("send", "Send it now through the mail server instead of saving a draft"),
            ],
            reply,
        ),
        command(
            "mail send",
            "Send real email now through the mail server; --draft ID sends a saved draft as it is",
            &["TOOL"],
            vec![
                flag("to", "ADDRS", TO),
                flag("cc", "ADDRS", CC),
                flag("bcc", "ADDRS", "Bcc recipients, comma-separated"),
                flag("subject", "TEXT", "Subject"),
                flag("body", "TEXT", BODY),
                switch("html", "The body is HTML"),
                flag("draft", "ID", "Send this saved draft instead (it leaves Drafts)"),
            ],
            send,
        ),
        command("mail sync", "Fetch new mail from the mail server now (runs in the background)", &["TOOL"], vec![], sync),
        command("mail contacts", "Find addresses you've mailed or received mail from", &["TOOL", "QUERY"], vec![], contacts),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("mail"))?;
    let (folder, search, page) = (args.flag("folder"), args.flag("search"), args.flag("page"));
    let mailbox = ctx.get(
        &format!("/tools/{}/mails", tool["id"].s()),
        &[("folder", folder.map(str::to_string)), ("q", search.map(str::to_string)), ("page", page.map(str::to_string))],
    )?;

    ctx.output(&mailbox, |ctx| {
        ctx.say(format!("{} (mail {}) {}", tool["name"].s(), tool["id"].s(), mailbox["account"]["email_address"].s()));
        let shown = mailbox["folder"].s();
        let view = VIEWS.iter().find(|(key, _)| *key == shown).map(|(_, name)| name.to_string()).unwrap_or(shown);
        let matching = search.map(|search| format!(" matching {}", quoted(search))).unwrap_or_default();
        ctx.say(format!(
            "{view}{matching}: {}, page {} of {}",
            count(mailbox["total_count"].int(), "conversation"),
            mailbox["page"].s(),
            mailbox["total_pages"].int().max(1)
        ));
        ctx.blank();

        let conversations = mailbox["conversations"].items();
        if conversations.is_empty() {
            ctx.say("  (no conversations)");
        }
        let rows = conversations
            .iter()
            .map(|conversation| {
                vec![
                    format!("{}/{}", tool["id"].s(), conversation["id"].s()),
                    moment(&conversation["sent_at"]).unwrap_or_default(),
                    if conversation["draft"].truthy() { "Draft".to_string() } else { conversation["from"].s() },
                    conversation["subject"].s(),
                    conversation_summary(conversation),
                ]
            })
            .collect();
        ctx.table(rows, 2);

        if mailbox["page"].int() < mailbox["total_pages"].int() {
            ctx.blank();
            let next = (mailbox["page"].int() + 1).to_string();
            let options: Vec<String> = [("folder", folder), ("search", search), ("page", Some(next.as_str()))]
                .into_iter()
                .filter_map(|(name, value)| value.map(|value| format!("--{name} {}", shell_escape(value))))
                .collect();
            ctx.say(format!("More: dobase mail list {} {}", tool["id"].s(), options.join(" ")));
        }
        ctx.blank();
        ctx.say(format!("Folders: {}", folder_summary(&mailbox)));
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "mail", "message")?;
    let html = args.on("html");
    let conversation = ctx.get(&format!("/tools/{}/mails/{id}", tool["id"].s()), &[])?;

    ctx.output(&conversation, |ctx| {
        let messages = conversation["messages"].items();
        ctx.say(format!("{} ({})", conversation["subject"].s(), count(messages.len() as i64, "message")));

        for message in messages {
            ctx.blank();
            ctx.say(format!(
                "[{}/{}] {} · {}",
                tool["id"].s(),
                message["id"].s(),
                address(&message["from_name"], &message["from_address"]),
                moment(&message["sent_at"]).unwrap_or_default()
            ));
            ctx.field("To", list_of(&message["to"]));
            ctx.field("Cc", list_of(&message["cc"]));
            ctx.field("Subject", message["subject"].s());
            ctx.field("Status", message_status(message));
            ctx.field("URL", message["url"].s());
            ctx.blank();

            let body = if html { message["body_html"].s() } else { message["body"].s() };
            if body.trim().is_empty() {
                ctx.say(format!("  (no {})", if html { "HTML" } else { "text" }));
            } else {
                ctx.paragraph(&body, 2);
            }

            let attachments = message["attachments"].items();
            if !attachments.is_empty() {
                ctx.blank();
                ctx.say("  Attachments:");
                let rows = attachments
                    .iter()
                    .map(|attachment| vec![attachment["filename"].s(), bytes(&attachment["file_size"]), attachment["download_url"].s()])
                    .collect();
                ctx.table(rows, 4);
            }

            for invite in message["calendar_invites"].items() {
                ctx.blank();
                let location = invite["location"].opt().filter(|location| !location.is_empty()).map(|location| format!(", {location}"));
                ctx.say(format!(
                    "  Invitation: {}, {} to {}{} ({})",
                    invite["summary"].s(),
                    moment(&invite["starts_at"]).unwrap_or_default(),
                    moment(&invite["ends_at"]).unwrap_or_default(),
                    location.unwrap_or_default(),
                    invite["status"].s()
                ));
            }
        }
        Ok(())
    })
}

fn read(ctx: &mut Ctx, args: &Args) -> Result<()> {
    change_message(ctx, args, true, "read", |message| format!("Marked {message} as read."))
}

fn unread(ctx: &mut Ctx, args: &Args) -> Result<()> {
    change_message(ctx, args, false, "read", |message| format!("Marked {message} as unread."))
}

fn star(ctx: &mut Ctx, args: &Args) -> Result<()> {
    change_message(ctx, args, true, "star", |message| format!("Starred {message}."))
}

fn unstar(ctx: &mut Ctx, args: &Args) -> Result<()> {
    change_message(ctx, args, false, "star", |message| format!("Unstarred {message}."))
}

fn archive(ctx: &mut Ctx, args: &Args) -> Result<()> {
    change_message(ctx, args, true, "archive", |message| format!("Archived {message}."))
}

fn unarchive(ctx: &mut Ctx, args: &Args) -> Result<()> {
    change_message(ctx, args, false, "archive", |message| format!("Unarchived {message}."))
}

fn move_message(ctx: &mut Ctx, args: &Args) -> Result<()> {
    // `mail list` shows views in lowercase; moving needs the folder names the server uses.
    let mut folder = args.at(1).to_string();
    if folder.eq_ignore_ascii_case("inbox") {
        folder = "INBOX".to_string();
    }
    if folder == "sent" {
        folder = "Sent".to_string();
    }
    if ["drafts", "starred", "archive", "trash"].contains(&folder.as_str()) {
        let hint = match folder.as_str() {
            "starred" => "; use `dobase mail star`",
            "archive" => "; use `dobase mail archive`",
            _ => "",
        };
        usage!("{folder} is a view, not a folder{hint}. Move to INBOX, Sent or a custom folder (see `dobase mail list`).");
    }

    let (tool, id) = ctx.tool_and_id(args.at(0), "mail", "message")?;
    let message = ctx.post(&format!("/tools/{}/mails/{id}/move", tool["id"].s()), json!({ "folder": folder }))?;
    ctx.output(&message, |ctx| {
        ctx.say(format!("Moved {} to {}.", describe(&tool, &message), message["folder"].s()));
        Ok(())
    })
}

fn draft(ctx: &mut Ctx, args: &Args) -> Result<()> {
    require_flags(args, &["to", "subject", "body"])?;
    let tool = ctx.tool(args.at(0), Some("mail"))?;

    let email = json!({
        "to": args.flag("to"),
        "cc": args.flag("cc"),
        "subject": ctx.text(args.flag("subject").unwrap())?,
        "body": ctx.rich_text(args.flag("body").unwrap(), args.on("html"))?,
    });
    let draft = ctx.post(&format!("/tools/{}/mails/drafts", tool["id"].s()), email)?;
    ctx.output(&draft, |ctx| {
        ctx.say(format!(
            "Saved draft {} to {}. Send it with: dobase mail send {} --draft {}",
            describe(&tool, &draft),
            list_of(&draft["to"]),
            tool["id"].s(),
            draft["id"].s()
        ));
        Ok(())
    })
}

fn reply(ctx: &mut Ctx, args: &Args) -> Result<()> {
    require_flags(args, &["body"])?;
    let (tool, id) = ctx.tool_and_id(args.at(0), "mail", "message")?;
    let conversation = ctx.get(&format!("/tools/{}/mails/{id}", tool["id"].s()), &[])?;
    let Some(original) = conversation["messages"].items().iter().find(|message| message["id"].int() == id) else {
        fail!("{}/{id} is not in its conversation.", tool["id"].s());
    };
    if original["draft"].truthy() {
        fail!("{0}/{id} is a draft. Send it with: dobase mail send {0} --draft {id}", tool["id"].s());
    }

    let (to, cc) = reply_recipients(original, &conversation["account"]["email_address"].s(), args.on("all"));
    if to.is_empty() {
        fail!("{}/{id} has no address to reply to.", tool["id"].s());
    }

    let reply = json!({
        "to": to.join(", "),
        "cc": cc.join(", "),
        "subject": format!("Re: {}", strip_reply_prefix(&original["subject"].s())),
        "body": ctx.rich_text(args.flag("body").unwrap(), args.on("html"))?,
        "in_reply_to": original["message_id"],
    });
    if args.on("send") {
        let sent = ctx.post(&format!("/tools/{}/mails", tool["id"].s()), reply)?;
        ctx.output(&sent, |ctx| {
            ctx.say(format!("Sent {} to {}.", quoted(&sent["subject"].s()), recipients(&sent)));
            Ok(())
        })
    } else {
        let draft = ctx.post(&format!("/tools/{}/mails/drafts", tool["id"].s()), reply)?;
        ctx.output(&draft, |ctx| {
            ctx.say(format!(
                "Saved reply draft {} to {}. Send it with: dobase mail send {} --draft {}",
                describe(&tool, &draft),
                recipients(&draft),
                tool["id"].s(),
                draft["id"].s()
            ));
            Ok(())
        })
    }
}

fn send(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("mail"))?;

    let request = if let Some(draft) = args.flag("draft") {
        if args.any(&["to", "cc", "bcc", "subject", "body", "html"]) {
            usage!("--draft sends the draft as it is saved; leave out --to, --cc, --bcc, --subject, --body and --html.");
        }
        let draft_id = draft.rsplit('/').next().filter(|id| is_digits(id) && (draft == *id || draft.len() > id.len() + 1));
        let Some(draft_id) = draft_id else {
            usage!("--draft expects a draft id like 21, got {}.", quoted(draft));
        };
        let draft_id: i64 = draft_id.parse().unwrap_or(0);

        let conversation = ctx.get(&format!("/tools/{}/mails/{draft_id}", tool["id"].s()), &[])?;
        let saved = conversation["messages"].items().iter().find(|message| message["id"].int() == draft_id).cloned().unwrap_or(Value::Null);
        if !saved["draft"].truthy() {
            fail!("{}/{draft_id} is not a draft.", tool["id"].s());
        }
        if saved["to"].items().is_empty() {
            fail!("Draft {}/{draft_id} has no recipients.", tool["id"].s());
        }

        let body = saved["body_html"].opt().unwrap_or_else(|| escape_html(&saved["body"].s()));
        json!({
            "to": list_of(&saved["to"]),
            "cc": list_of(&saved["cc"]),
            "subject": saved["subject"],
            "body": body,
            "in_reply_to": saved["in_reply_to"],
            "draft_id": saved["id"],
        })
    } else {
        require_flags(args, &["to", "subject", "body"])?;
        json!({
            "to": args.flag("to"),
            "cc": args.flag("cc"),
            "bcc": args.flag("bcc"),
            "subject": ctx.text(args.flag("subject").unwrap())?,
            "body": ctx.rich_text(args.flag("body").unwrap(), args.on("html"))?,
        })
    };

    let sent = ctx.post(&format!("/tools/{}/mails", tool["id"].s()), request)?;
    ctx.output(&sent, |ctx| {
        ctx.say(format!("Sent {} to {}.", quoted(&sent["subject"].s()), recipients(&sent)));
        Ok(())
    })
}

fn sync(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("mail"))?;
    let status = ctx.post(&format!("/tools/{}/sync", tool["id"].s()), json!({}))?;
    ctx.output(&status, |ctx| {
        ctx.say(format!(
            "Syncing {} (mail {}) in the background. Last synced: {}.",
            tool["name"].s(),
            tool["id"].s(),
            moment(&status["last_synced_at"]).unwrap_or_else(|| "never".to_string())
        ));
        Ok(())
    })
}

fn contacts(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let query = args.at(1).trim();
    if query.chars().count() < 2 {
        usage!("QUERY needs at least 2 characters.");
    }

    let tool = ctx.tool(args.at(0), Some("mail"))?;
    let contacts = ctx.get(&format!("/tools/{}/mails_contacts", tool["id"].s()), &[("q", Some(query.to_string()))])?;
    ctx.output(&contacts, |ctx| {
        if contacts.items().is_empty() {
            ctx.say(format!("Nobody matches {}.", quoted(args.at(1))));
        }
        for contact in contacts.items() {
            ctx.say(address(&contact["name"], &contact["email_address"]));
        }
        Ok(())
    })
}

fn change_message(ctx: &mut Ctx, args: &Args, add: bool, action: &str, done: fn(String) -> String) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "mail", "message")?;
    let path = format!("/tools/{}/mails/{id}/{action}", tool["id"].s());
    let message = if add { ctx.post(&path, json!({}))? } else { ctx.delete(&path)? };
    ctx.output(&message, |ctx| {
        ctx.say(done(describe(&tool, &message)));
        Ok(())
    })
}

fn require_flags(args: &Args, names: &[&str]) -> Result<()> {
    let missing: Vec<String> = names.iter().filter(|name| args.flag(name).is_none()).map(|name| format!("--{name}")).collect();
    if missing.is_empty() { Ok(()) } else { Err(Error::usage(format!("Missing {}. See `dobase help mail`.", missing.join(", ")))) }
}

/// Like other mail clients, a reply to a message you sent goes to its recipients.
pub fn reply_recipients(message: &Value, own_address: &str, all: bool) -> (Vec<String>, Vec<String>) {
    let own = |address: &str| address.eq_ignore_ascii_case(own_address);
    let addresses = |value: &Value| value.items().iter().map(Json::s).collect::<Vec<_>>();

    let from = message["from_address"].opt();
    let to = if from.as_deref().is_some_and(own) { addresses(&message["to"]) } else { from.into_iter().collect() };

    let mut cc: Vec<String> = Vec::new();
    if all {
        for address in addresses(&message["to"]).into_iter().chain(addresses(&message["cc"])) {
            let taken = own(&address)
                || to.iter().any(|recipient| recipient.eq_ignore_ascii_case(&address))
                || cc.iter().any(|recipient| recipient.eq_ignore_ascii_case(&address));
            if !taken {
                cc.push(address);
            }
        }
    }
    (to, cc)
}

fn strip_reply_prefix(subject: &str) -> String {
    for prefix in ["re:", "fwd:", "fw:"] {
        if subject.len() >= prefix.len() && subject.is_char_boundary(prefix.len()) && subject[..prefix.len()].eq_ignore_ascii_case(prefix) {
            return subject[prefix.len()..].trim().to_string();
        }
    }
    subject.trim().to_string()
}

fn describe(tool: &Value, message: &Value) -> String {
    let subject = message["subject"].s();
    let subject = if subject.is_empty() { "(no subject)".to_string() } else { quoted(&subject) };
    format!("{}/{} {subject}", tool["id"].s(), message["id"].s())
}

fn address(name: &Value, email: &Value) -> String {
    let name = name.s();
    if name.is_empty() { email.s() } else { format!("{name} <{}>", email.s()) }
}

fn list_of(addresses: &Value) -> String {
    addresses.items().iter().map(Json::s).collect::<Vec<_>>().join(", ")
}

fn recipients(email: &Value) -> String {
    join(
        [
            Some(list_of(&email["to"])),
            (!email["cc"].items().is_empty()).then(|| format!("cc {}", list_of(&email["cc"]))),
            (!email["bcc"].items().is_empty()).then(|| format!("bcc {}", list_of(&email["bcc"]))),
        ],
        "; ",
    )
}

fn conversation_summary(conversation: &Value) -> String {
    join(
        [
            (!conversation["read"].truthy()).then(|| "unread".to_string()),
            conversation["starred"].truthy().then(|| "starred".to_string()),
            (conversation["messages_count"].int() > 1).then(|| count(conversation["messages_count"].int(), "message")),
            conversation["has_attachments"].truthy().then(|| "attachments".to_string()),
        ],
        "  ",
    )
}

fn message_status(message: &Value) -> String {
    join(
        [
            message["draft"].truthy().then(|| "draft".to_string()),
            Some(if message["read"].truthy() { "read" } else { "unread" }.to_string()),
            message["starred"].truthy().then(|| "starred".to_string()),
            message["archived"].truthy().then(|| "archived".to_string()),
            message["trashed"].truthy().then(|| "in trash".to_string()),
            (!message["draft"].truthy()).then(|| format!("folder {}", message["folder"].s())),
        ],
        ", ",
    )
}

fn folder_summary(mailbox: &Value) -> String {
    let counts = &mailbox["counts"];
    let mut names: Vec<String> = mailbox["folders"]
        .items()
        .iter()
        .map(|name| {
            let name = name.s();
            let (number, label) = match name.as_str() {
                "inbox" => (counts["inbox_unread"].int(), " unread"),
                "drafts" => (counts["drafts"].int(), ""),
                "trash" => (counts["trash"].int(), ""),
                _ => (0, ""),
            };
            if number > 0 { format!("{name} ({number}{label})") } else { name }
        })
        .collect();
    names.extend(mailbox["custom_folders"].items().iter().map(Json::s));
    names.join(", ")
}

/// Quotes a value for a shell command line, like Ruby's Shellwords.escape.
fn shell_escape(value: &str) -> String {
    if value.is_empty() {
        return "''".to_string();
    }
    value
        .chars()
        .map(|char| {
            if char.is_ascii_alphanumeric() || "_-.,:+/@".contains(char) || !char.is_ascii() {
                char.to_string()
            } else if char == '\n' {
                "'\n'".to_string()
            } else {
                format!("\\{char}")
            }
        })
        .collect()
}

use serde_json::{Value, json};

use crate::command::{Args, Ctx, Definition, Result, bytes, command, flag, moment, quoted, switch, usage};
use crate::value::{Json, compact, is_digits};

/// The emoji the app offers; anything else is refused.
const REACTIONS: [&str; 8] = ["👍", "❤️", "😂", "🎉", "😮", "🙏", "👀", "✅"];

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "chat list",
            "Show the latest messages in a chat, oldest first (doesn't mark it read)",
            &["TOOL"],
            vec![
                flag("limit", "N", "Number of messages (default 50, max 200)"),
                flag("before", "ID", "Only messages older than this message, to page back"),
            ],
            list,
        ),
        command(
            "chat post",
            "Send a message to a chat",
            &["TOOL", "TEXT"],
            vec![switch("html", "TEXT is HTML"), flag("reply-to", "ID", "Reply to this message")],
            post,
        ),
        command(
            "chat edit",
            "Change the text of one of your messages",
            &["TOOL/MESSAGE", "TEXT"],
            vec![switch("html", "TEXT is HTML")],
            edit,
        ),
        command("chat delete", "Delete a message (your own, or anyone's if you own the chat)", &["TOOL/MESSAGE"], vec![], delete),
        command(
            "chat react",
            format!("Put an emoji on a message, or take yours off ({})", REACTIONS.join(" ")),
            &["TOOL/MESSAGE", "EMOJI"],
            vec![switch("remove", "Take your emoji off instead")],
            react,
        ),
        command("chat read", "Mark a chat as read up to its latest message", &["TOOL"], vec![], read),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("chat"))?;
    let limit = args.flag("limit");
    let before = args.flag("before").map(message_id).transpose()?;
    let chat = ctx.get(&format!("/tools/{}/chat", tool["id"].s()), &[("limit", limit.map(str::to_string)), ("before", before)])?;

    ctx.output(&chat, |ctx| {
        let messages = chat["messages"].items();
        ctx.say(format!("{} (chat {}) {}", tool["name"].s(), tool["id"].s(), chat["url"].s()));
        if messages.is_empty() {
            ctx.say("  (no messages)");
        }
        if chat["has_more"].truthy() {
            let limit = limit.map(|limit| format!(" --limit {limit}")).unwrap_or_default();
            let oldest = messages.first().map(|message| message["id"].s()).unwrap_or_default();
            ctx.say(format!("  Older messages: dobase chat list {} --before {oldest}{limit}", tool["id"].s()));
        }

        for message in messages {
            ctx.blank();
            let author = message["user"]["name"].opt().unwrap_or_else(|| "Former member".to_string());
            let edited = if message["edited_at"].truthy() { " (edited)" } else { "" };
            ctx.say(format!(
                "{author} · {}{edited} [message {}/{}]",
                moment(&message["created_at"]).unwrap_or_default(),
                tool["id"].s(),
                message["id"].s()
            ));
            if message["reply_to"].truthy() {
                ctx.say(format!("  > {}: {}", message["reply_to"]["user_name"].s(), message["reply_to"]["preview"].s()));
            }
            ctx.paragraph(&message["body"].s(), 2);
            for file in message["files"].items() {
                ctx.say(format!("  File: {} ({}) {}", file["filename"].s(), bytes(&file["byte_size"]), file["download_url"].s()));
            }
            let reactions: Vec<String> = message["reactions"]
                .items()
                .iter()
                .map(|reaction| {
                    let names: Vec<String> = reaction["users"].items().iter().map(|user| user["name"].s()).collect();
                    format!("{} {}", reaction["emoji"].s(), names.join(", "))
                })
                .collect();
            if !reactions.is_empty() {
                ctx.say(format!("  Reactions: {}", reactions.join(" · ")));
            }
        }
        Ok(())
    })
}

fn post(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("chat"))?;
    let reply_to = args.flag("reply-to").map(message_id).transpose()?;
    let body = ctx.rich_text(args.at(1), args.on("html"))?;

    let message = ctx.post(
        &format!("/tools/{}/chat/messages", tool["id"].s()),
        json!({ "message": compact(json!({ "body": body, "reply_to_id": reply_to })) }),
    )?;
    ctx.output(&message, |ctx| {
        ctx.say(format!("Posted message {}/{} to {}.", tool["id"].s(), message["id"].s(), tool["name"].s()));
        Ok(())
    })
}

fn edit(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "chat", "message")?;
    let body = ctx.rich_text(args.at(1), args.on("html"))?;
    let message = ctx.patch(&format!("/tools/{}/chat/messages/{id}", tool["id"].s()), json!({ "message": { "body": body } }))?;
    ctx.output(&message, |ctx| {
        ctx.say(format!("Edited message {}/{}.", tool["id"].s(), message["id"].s()));
        Ok(())
    })
}

fn delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "chat", "message")?;
    ctx.delete(&format!("/tools/{}/chat/messages/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted message {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn react(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "chat", "message")?;
    let (emoji, remove) = (args.at(1), args.on("remove"));
    let path = format!("/tools/{}/chat/messages/{id}/reactions", tool["id"].s());

    let message = if remove {
        let encoded: String = url::form_urlencoded::byte_serialize(emoji.as_bytes()).collect();
        ctx.delete(&format!("{path}/{encoded}"))?
    } else {
        ctx.post(&path, json!({ "emoji": emoji }))?
    };
    ctx.output(&message, |ctx| {
        let action = if remove { format!("Took {emoji} off") } else { format!("Put {emoji} on") };
        ctx.say(format!("{action} message {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn read(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("chat"))?;
    let receipt = ctx.post(&format!("/tools/{}/chat/read", tool["id"].s()), json!({}))?;
    ctx.output(&receipt, |ctx| {
        ctx.say(format!("Marked {} as read.", tool["name"].s()));
        Ok(())
    })
}

/// A message id, or a TOOL/MESSAGE reference as printed by `chat list`.
fn message_id(value: &str) -> Result<String> {
    let id = value.rsplit('/').next().unwrap_or("");
    if !is_digits(id) {
        usage!("Expected a message id like 104, got {}.", quoted(value));
    }
    Ok(id.to_string())
}

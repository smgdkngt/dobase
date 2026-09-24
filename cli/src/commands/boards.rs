use serde_json::{Map, Value, json};

use crate::command::{
    Args, Ctx, Definition, Flag, Result, bytes, command, count, date_param, fail, flag, moment, person, quoted, switch, usage,
};
use crate::value::{Json, compact, join};

const COLORS: [&str; 6] = ["red", "orange", "yellow", "green", "blue", "purple"];

fn card_flags() -> Vec<Flag> {
    vec![
        flag("description", "TEXT", "Description (plain text, or HTML with --html)"),
        switch("html", "The description is HTML"),
        flag("due", "DATE", "Due date: YYYY-MM-DD, today, tomorrow or none"),
        flag("assignee", "USER", "me, none, a user id, email or name"),
        flag("color", "COLOR", format!("{} or none", COLORS.join(", "))),
    ]
}

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "card list",
            "Show a board: its columns and their cards",
            &["TOOL"],
            vec![switch("archived", "Show archived cards instead of active ones")],
            list,
        ),
        command("card show", "Show a card with its description, comments and attachments", &["TOOL/CARD"], vec![], show),
        command(
            "card create",
            "Add a card to a board (to the first column unless --column)",
            &["TOOL", "TITLE"],
            [card_flags(), vec![flag("column", "COLUMN", "Column id or name")]].concat(),
            create,
        ),
        command(
            "card update",
            "Change a card's title, description, due date, assignee or color",
            &["TOOL/CARD"],
            [card_flags(), vec![flag("title", "TEXT", "New title")]].concat(),
            update,
        ),
        command(
            "card move",
            "Move a card to another column, or to a position within its column",
            &["TOOL/CARD", "[COLUMN]"],
            vec![flag("position", "N", "Position in the column, 1 = top (default: bottom)")],
            move_card,
        ),
        command("card archive", "Archive a card (reversible with card unarchive)", &["TOOL/CARD"], vec![], archive),
        command("card unarchive", "Bring an archived card back", &["TOOL/CARD"], vec![], unarchive),
        command("card delete", "Delete a card permanently, with its comments and attachments", &["TOOL/CARD"], vec![], delete),
        command("card comment", "Comment on a card", &["TOOL/CARD", "TEXT"], vec![switch("html", "TEXT is HTML")], comment),
        command("card attach", "Attach files to a card (25 MB max each)", &["TOOL/CARD", "PATH..."], vec![], attach),
        command("column create", "Add a column to the end of a board", &["TOOL", "NAME"], vec![], column_create),
        command("column rename", "Rename a column", &["TOOL/COLUMN", "NAME"], vec![], column_rename),
        command("column delete", "Delete a column and every card in it", &["TOOL/COLUMN"], vec![], column_delete),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let archived = args.on("archived");
    let tool = ctx.tool(args.at(0), Some("boards"))?;
    let board = ctx.get(&format!("/tools/{}/board", tool["id"].s()), &[("archived", archived.then(|| "true".to_string()))])?;

    ctx.output(&board, |ctx| {
        ctx.say(format!("{} (board {}) {}", tool["name"].s(), tool["id"].s(), board["url"].s()));
        for column in board["columns"].items() {
            ctx.blank();
            ctx.say(format!("{} [column {}]", column["name"].s(), column["id"].s()));
            let cards = column["cards"].items();
            if cards.is_empty() {
                ctx.say(format!("  (no {}cards)", if archived { "archived " } else { "" }));
            }
            let rows = cards
                .iter()
                .map(|card| vec![format!("{}/{}", tool["id"].s(), card["id"].s()), card["title"].s(), card_summary(card)])
                .collect();
            ctx.table(rows, 2);
        }
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let card = ctx.get(&format!("/tools/{}/board/cards/{id}", tool["id"].s()), &[])?;

    ctx.output(&card, |ctx| {
        ctx.say(format!("{} (card {}/{})", card["title"].s(), tool["id"].s(), card["id"].s()));
        ctx.field("Board", format!("{} › {}", tool["name"].s(), card["column"]["name"].s()));
        ctx.field("Assignee", person(&card["assignee"]));
        ctx.field("Due", card["due_date"].s());
        ctx.field("Color", card["color"].s());
        if card["archived"].truthy() {
            ctx.field("Archived", "yes".to_string());
        }
        ctx.field("Created", join([moment(&card["created_at"]), card["creator"]["name"].opt()], " by "));
        ctx.field("URL", card["url"].s());
        show_details(ctx, &card);
        Ok(())
    })
}

/// The description, comments and attachments of a card or todo.
pub fn show_details(ctx: &mut Ctx, record: &Value) {
    let description = record["description"].s();
    if !description.trim().is_empty() {
        ctx.blank();
        ctx.say("Description:");
        ctx.paragraph(&description, 2);
    }

    let comments = record["comments"].items();
    ctx.blank();
    ctx.say(format!("Comments ({}):", comments.len()));
    for comment in comments {
        let author = comment["user"]["name"].opt().unwrap_or_else(|| "Former member".to_string());
        ctx.say(format!("  {author} · {} [comment {}]", moment(&comment["created_at"]).unwrap_or_default(), comment["id"].s()));
        ctx.paragraph(&comment["body"].s(), 4);
    }

    let attachments = record["attachments"].items();
    if !attachments.is_empty() {
        ctx.blank();
        ctx.say(format!("Attachments ({}):", attachments.len()));
        let rows = attachments
            .iter()
            .map(|attachment| vec![attachment["filename"].s(), bytes(&attachment["file_size"]), attachment["download_url"].s()])
            .collect();
        ctx.table(rows, 2);
    }
}

fn create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("boards"))?;
    let target = find_column(ctx, &tool, args.flag("column"))?;

    let mut attributes = card_attributes(ctx, &tool, args)?;
    attributes.insert("title".into(), json!(args.at(1)));
    let card = ctx.post(&format!("/columns/{}/cards", target["id"].s()), json!({ "card": attributes }))?;
    ctx.output(&card, |ctx| {
        ctx.say(format!(
            "Created card {}/{} {} in {}: {}",
            tool["id"].s(),
            card["id"].s(),
            quoted(&card["title"].s()),
            target["name"].s(),
            card["url"].s()
        ));
        Ok(())
    })
}

fn update(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let mut attributes = card_attributes(ctx, &tool, args)?;
    if let Some(title) = args.flag("title") {
        attributes.insert("title".into(), json!(title));
    }
    if attributes.is_empty() {
        usage!("Nothing to update. See `dobase help card`.");
    }

    let card = ctx.patch(&format!("/tools/{}/board/cards/{id}", tool["id"].s()), json!({ "card": attributes }))?;
    ctx.output(&card, |ctx| {
        ctx.say(format!("Updated card {}/{} {}.", tool["id"].s(), card["id"].s(), quoted(&card["title"].s())));
        Ok(())
    })
}

fn move_card(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let (column, position) = (args.get(1), args.flag("position"));
    if column.is_none() && position.is_none() {
        usage!("Give a COLUMN, a --position, or both.");
    }

    let target = match column {
        Some(column) => find_column(ctx, &tool, Some(column))?["id"].clone(),
        None => Value::Null,
    };
    let body = compact(json!({ "column_id": target, "position": position.map(zero_based) }));
    let card = ctx.patch(&format!("/tools/{}/board/cards/{id}/position", tool["id"].s()), body)?;
    ctx.output(&card, |ctx| {
        ctx.say(format!(
            "Moved card {}/{} {} to {}, position {}.",
            tool["id"].s(),
            card["id"].s(),
            quoted(&card["title"].s()),
            card["column"]["name"].s(),
            card["position"].int() + 1
        ));
        Ok(())
    })
}

/// "3" (1 = top) as the API's 0-based position.
pub fn zero_based(position: &str) -> i64 {
    (position.trim().parse::<i64>().unwrap_or(0) - 1).max(0)
}

fn archive(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let card = ctx.post(&format!("/tools/{}/board/cards/{id}/archive", tool["id"].s()), json!({}))?;
    ctx.output(&card, |ctx| {
        ctx.say(format!("Archived card {}/{} {}.", tool["id"].s(), card["id"].s(), quoted(&card["title"].s())));
        Ok(())
    })
}

fn unarchive(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let card = ctx.delete(&format!("/tools/{}/board/cards/{id}/archive", tool["id"].s()))?;
    ctx.output(&card, |ctx| {
        ctx.say(format!("Unarchived card {}/{} {}.", tool["id"].s(), card["id"].s(), quoted(&card["title"].s())));
        Ok(())
    })
}

fn delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    ctx.delete(&format!("/tools/{}/board/cards/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted card {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn comment(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let body = ctx.rich_text(args.at(1), args.on("html"))?;
    let comment = ctx.post(&format!("/tools/{}/board/cards/{id}/comments", tool["id"].s()), json!({ "body": body }))?;
    ctx.output(&comment, |ctx| {
        ctx.say(format!("Commented on card {}/{id} [comment {}].", tool["id"].s(), comment["id"].s()));
        Ok(())
    })
}

fn attach(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "card")?;
    let path = format!("/tools/{}/board/cards/{id}/attachments", tool["id"].s());
    let label = format!("card {}/{id}", tool["id"].s());
    attach_files(ctx, &path, args.rest(1), &label)
}

/// Uploads each file as an attachment to `path`, one request per file.
pub fn attach_files(ctx: &mut Ctx, path: &str, files: &[String], label: &str) -> Result<()> {
    let missing: Vec<&str> = files.iter().filter(|file| !std::path::Path::new(file).is_file()).map(String::as_str).collect();
    if !missing.is_empty() {
        usage!("No such file: {}", missing.join(", "));
    }

    let mut attachments = Vec::new();
    for file in files {
        attachments.push(ctx.api()?.upload(path, &[("file", file)], &[])?);
    }
    ctx.output(&json!(attachments), |ctx| {
        for attachment in &attachments {
            ctx.say(format!("Attached {} ({}) to {label}.", attachment["filename"].s(), bytes(&attachment["file_size"])));
        }
        Ok(())
    })
}

fn column_create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("boards"))?;
    let column = ctx.post(&format!("/tools/{}/board/columns", tool["id"].s()), json!({ "name": args.at(1) }))?;
    ctx.output(&column, |ctx| {
        ctx.say(format!("Created column {}/{} {}.", tool["id"].s(), column["id"].s(), quoted(&column["name"].s())));
        Ok(())
    })
}

fn column_rename(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "column")?;
    let column = ctx.patch(&format!("/tools/{}/board/columns/{id}", tool["id"].s()), json!({ "name": args.at(1) }))?;
    ctx.output(&column, |ctx| {
        ctx.say(format!("Renamed column {}/{} to {}.", tool["id"].s(), column["id"].s(), quoted(&column["name"].s())));
        Ok(())
    })
}

fn column_delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "boards", "column")?;
    ctx.delete(&format!("/tools/{}/board/columns/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted column {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn card_summary(card: &Value) -> String {
    join(
        [
            card["due_date"].opt().map(|due| format!("due {due}")),
            card["assignee"].truthy().then(|| format!("@{}", card["assignee"]["name"].s())),
            card["color"].opt(),
            (card["comments_count"].int() > 0).then(|| count(card["comments_count"].int(), "comment")),
            (card["attachments_count"].int() > 0).then(|| count(card["attachments_count"].int(), "file")),
        ],
        "  ",
    )
}

/// The first column, or the one whose id or name (or the start of it) is `reference`.
fn find_column(ctx: &mut Ctx, tool: &Value, reference: Option<&str>) -> Result<Value> {
    let board = ctx.get(&format!("/tools/{}/board", tool["id"].s()), &[])?;
    find_named(board["columns"].items(), reference, "name", "column", "Columns", &tool["name"].s())
}

/// Finds a column, list or calendar by id, name, or the start of its name.
pub fn find_named(items: &[Value], reference: Option<&str>, key: &str, what: &str, plural: &str, owner: &str) -> Result<Value> {
    let Some(reference) = reference else {
        return match items.first() {
            Some(first) => Ok(first.clone()),
            None => fail!("{owner} has no {what}s."),
        };
    };

    let lower = reference.to_lowercase();
    let found = items
        .iter()
        .find(|item| item["id"].s() == reference)
        .or_else(|| items.iter().find(|item| item[key].s().to_lowercase() == lower))
        .or_else(|| items.iter().find(|item| item[key].s().to_lowercase().starts_with(&lower)));
    match found {
        Some(item) => Ok(item.clone()),
        None => {
            let names: Vec<String> = items.iter().map(|item| item[key].s()).collect();
            fail!("No {what} matches {}. {plural}: {}", quoted(reference), names.join(", "))
        }
    }
}

fn card_attributes(ctx: &mut Ctx, tool: &Value, args: &Args) -> Result<Map<String, Value>> {
    let mut attributes = Map::new();
    if let Some(description) = args.flag("description") {
        attributes.insert("description".into(), json!(ctx.rich_text(description, args.on("html"))?));
    }
    if let Some(due) = args.flag("due") {
        attributes.insert("due_date".into(), json!(date_param(due)?));
    }
    if let Some(assignee) = args.flag("assignee") {
        attributes.insert("assigned_user_id".into(), ctx.user_id(tool, assignee)?);
    }
    if let Some(color) = args.flag("color") {
        if !COLORS.contains(&color) && color != "none" {
            usage!("--color must be one of: {}, none", COLORS.join(", "));
        }
        attributes.insert("color".into(), json!(if color == "none" { "" } else { color }));
    }
    Ok(attributes)
}

use serde_json::{Map, Value, json};

use super::boards::{attach_files, find_named, show_details, zero_based};
use crate::command::{Args, Ctx, Definition, Flag, Result, command, count, date_param, day, flag, moment, person, quoted, switch, usage};
use crate::value::{Json, compact, join};

const REPEATS: [&str; 3] = ["daily", "weekly", "monthly"];

fn item_flags() -> Vec<Flag> {
    vec![
        flag("description", "TEXT", "Description (plain text, or HTML with --html)"),
        switch("html", "The description is HTML"),
        flag("due", "DATE", "Due date: YYYY-MM-DD, today, tomorrow or none"),
        flag("assignee", "USER", "me, none, a user id, email or name"),
        flag("repeat", "RULE", format!("{} or none", REPEATS.join(", "))),
    ]
}

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "todo list",
            "Show a todos tool: its lists with their open and recently completed todos",
            &["TOOL"],
            vec![switch("completed", "Show every completed todo instead")],
            list,
        ),
        command("todo show", "Show a todo with its description, comments and attachments", &["TOOL/ITEM"], vec![], show),
        command(
            "todo create",
            "Add a todo to the bottom of a list (the first list unless --list)",
            &["TOOL", "TITLE"],
            [item_flags(), vec![flag("list", "LIST", "List id or name")]].concat(),
            create,
        ),
        command(
            "todo update",
            "Change a todo's title, description, due date, assignee or repeat",
            &["TOOL/ITEM"],
            [item_flags(), vec![flag("title", "TEXT", "New title")]].concat(),
            update,
        ),
        command("todo finish", "Mark a todo as done (a repeating todo comes back with its next due date)", &["TOOL/ITEM"], vec![], finish),
        command("todo reopen", "Mark a completed todo as not done", &["TOOL/ITEM"], vec![], reopen),
        command(
            "todo move",
            "Move a todo to another list, or to a position within its list",
            &["TOOL/ITEM", "[LIST]"],
            vec![flag("position", "N", "Position in the list, 1 = top (default: bottom)")],
            move_item,
        ),
        command("todo delete", "Delete a todo permanently, with its comments and attachments", &["TOOL/ITEM"], vec![], delete),
        command("todo comment", "Comment on a todo", &["TOOL/ITEM", "TEXT"], vec![switch("html", "TEXT is HTML")], comment),
        command("todo attach", "Attach files to a todo (25 MB max each)", &["TOOL/ITEM", "PATH..."], vec![], attach),
        command("todolist create", "Add a list to the end of a todos tool", &["TOOL", "TITLE"], vec![], list_create),
        command("todolist rename", "Rename a list", &["TOOL/LIST", "TITLE"], vec![], list_rename),
        command("todolist delete", "Delete a list and every todo on it", &["TOOL/LIST"], vec![], list_delete),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let completed = args.on("completed");
    let tool = ctx.tool(args.at(0), Some("todos"))?;
    let todo = ctx.get(&format!("/tools/{}/todo", tool["id"].s()), &[("completed", completed.then(|| "true".to_string()))])?;

    ctx.output(&todo, |ctx| {
        ctx.say(format!("{} (todos {}) {}", tool["name"].s(), tool["id"].s(), todo["url"].s()));
        for list in todo["lists"].items() {
            ctx.blank();
            ctx.say(format!("{} [list {}]", list["title"].s(), list["id"].s()));
            let items = list["items"].items();
            if items.is_empty() {
                ctx.say(format!("  (no {}todos)", if completed { "completed " } else { "" }));
            }
            let rows = items
                .iter()
                .map(|item| {
                    vec![
                        format!("{}/{}", tool["id"].s(), item["id"].s()),
                        if item["completed"].truthy() { "[x]" } else { "[ ]" }.to_string(),
                        item["title"].s(),
                        item_summary(item),
                    ]
                })
                .collect();
            ctx.table(rows, 2);
        }
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let item = ctx.get(&format!("/tools/{}/todo/items/{id}", tool["id"].s()), &[])?;

    ctx.output(&item, |ctx| {
        ctx.say(format!("{} (todo {}/{})", item["title"].s(), tool["id"].s(), item["id"].s()));
        ctx.field("List", format!("{} › {}", tool["name"].s(), item["list"]["title"].s()));
        let status = if item["completed"].truthy() {
            format!("done {}", moment(&item["completed_at"]).unwrap_or_default())
        } else {
            "open".to_string()
        };
        ctx.field("Status", status);
        ctx.field("Assignee", person(&item["assignee"]));
        ctx.field("Due", item["due_date"].s());
        ctx.field("Repeats", item["recurrence_rule"].s());
        ctx.field("Created", join([moment(&item["created_at"]), item["creator"]["name"].opt()], " by "));
        ctx.field("URL", item["url"].s());
        show_details(ctx, &item);
        Ok(())
    })
}

fn create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("todos"))?;
    let target = find_list(ctx, &tool, args.flag("list"))?;

    let mut attributes = item_attributes(ctx, &tool, args)?;
    attributes.insert("title".into(), json!(args.at(1)));
    let item = ctx.post(&format!("/todo_lists/{}/items", target["id"].s()), json!({ "item": attributes }))?;
    ctx.output(&item, |ctx| {
        ctx.say(format!(
            "Created todo {}/{} {} in {}: {}",
            tool["id"].s(),
            item["id"].s(),
            quoted(&item["title"].s()),
            target["title"].s(),
            item["url"].s()
        ));
        Ok(())
    })
}

fn update(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let mut attributes = item_attributes(ctx, &tool, args)?;
    if let Some(title) = args.flag("title") {
        attributes.insert("title".into(), json!(title));
    }
    if attributes.is_empty() {
        usage!("Nothing to update. See `dobase help todo`.");
    }

    let item = ctx.patch(&format!("/tools/{}/todo/items/{id}", tool["id"].s()), json!({ "item": attributes }))?;
    ctx.output(&item, |ctx| {
        ctx.say(format!("Updated todo {}/{} {}.", tool["id"].s(), item["id"].s(), quoted(&item["title"].s())));
        Ok(())
    })
}

fn finish(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let item = ctx.post(&format!("/tools/{}/todo/items/{id}/completion", tool["id"].s()), json!({}))?;

    ctx.output(&item, |ctx| {
        ctx.say(format!("Completed todo {}/{} {}.", tool["id"].s(), item["id"].s(), quoted(&item["title"].s())));
        if let Some(rule) = item["recurrence_rule"].opt() {
            ctx.say(format!("It repeats {rule}, so the next one is on the list."));
        }
        Ok(())
    })
}

fn reopen(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let item = ctx.delete(&format!("/tools/{}/todo/items/{id}/completion", tool["id"].s()))?;
    ctx.output(&item, |ctx| {
        ctx.say(format!("Reopened todo {}/{} {}.", tool["id"].s(), item["id"].s(), quoted(&item["title"].s())));
        Ok(())
    })
}

fn move_item(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let (list, position) = (args.get(1), args.flag("position"));
    if list.is_none() && position.is_none() {
        usage!("Give a LIST, a --position, or both.");
    }

    let target = match list {
        Some(list) => find_list(ctx, &tool, Some(list))?["id"].clone(),
        None => Value::Null,
    };
    let body = compact(json!({ "todo_list_id": target, "position": position.map(zero_based) }));
    let item = ctx.patch(&format!("/tools/{}/todo/items/{id}/position", tool["id"].s()), body)?;
    ctx.output(&item, |ctx| {
        ctx.say(format!(
            "Moved todo {}/{} {} to {}, position {}.",
            tool["id"].s(),
            item["id"].s(),
            quoted(&item["title"].s()),
            item["list"]["title"].s(),
            item["position"].int() + 1
        ));
        Ok(())
    })
}

fn delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    ctx.delete(&format!("/tools/{}/todo/items/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted todo {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn comment(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let body = ctx.rich_text(args.at(1), args.on("html"))?;
    let comment = ctx.post(&format!("/tools/{}/todo/items/{id}/comments", tool["id"].s()), json!({ "body": body }))?;
    ctx.output(&comment, |ctx| {
        ctx.say(format!("Commented on todo {}/{id} [comment {}].", tool["id"].s(), comment["id"].s()));
        Ok(())
    })
}

fn attach(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "item")?;
    let path = format!("/tools/{}/todo/items/{id}/attachments", tool["id"].s());
    let label = format!("todo {}/{id}", tool["id"].s());
    attach_files(ctx, &path, args.rest(1), &label)
}

fn list_create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("todos"))?;
    let list = ctx.post(&format!("/tools/{}/todo/lists", tool["id"].s()), json!({ "title": args.at(1) }))?;
    ctx.output(&list, |ctx| {
        ctx.say(format!("Created list {}/{} {}.", tool["id"].s(), list["id"].s(), quoted(&list["title"].s())));
        Ok(())
    })
}

fn list_rename(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "list")?;
    let list = ctx.patch(&format!("/tools/{}/todo/lists/{id}", tool["id"].s()), json!({ "title": args.at(1) }))?;
    ctx.output(&list, |ctx| {
        ctx.say(format!("Renamed list {}/{} to {}.", tool["id"].s(), list["id"].s(), quoted(&list["title"].s())));
        Ok(())
    })
}

fn list_delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "todos", "list")?;
    ctx.delete(&format!("/tools/{}/todo/lists/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted list {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn item_summary(item: &Value) -> String {
    join(
        [
            item["completed"].truthy().then(|| format!("done {}", day(&item["completed_at"]).unwrap_or_default())),
            item["due_date"].opt().map(|due| format!("due {due}")),
            item["assignee"].truthy().then(|| format!("@{}", item["assignee"]["name"].s())),
            item["recurrence_rule"].opt().map(|rule| format!("repeats {rule}")),
            (item["comments_count"].int() > 0).then(|| count(item["comments_count"].int(), "comment")),
            (item["attachments_count"].int() > 0).then(|| count(item["attachments_count"].int(), "file")),
        ],
        "  ",
    )
}

fn find_list(ctx: &mut Ctx, tool: &Value, reference: Option<&str>) -> Result<Value> {
    let todo = ctx.get(&format!("/tools/{}/todo", tool["id"].s()), &[])?;
    find_named(todo["lists"].items(), reference, "title", "list", "Lists", &tool["name"].s())
}

fn item_attributes(ctx: &mut Ctx, tool: &Value, args: &Args) -> Result<Map<String, Value>> {
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
    if let Some(repeat) = args.flag("repeat") {
        if !REPEATS.contains(&repeat) && repeat != "none" {
            usage!("--repeat must be one of: {}, none", REPEATS.join(", "));
        }
        attributes.insert("recurrence_rule".into(), if repeat == "none" { Value::Null } else { json!(repeat) });
    }
    Ok(attributes)
}

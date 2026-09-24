use serde_json::json;

use crate::command::{Args, Ctx, Definition, Result, command, flag, person, quoted, usage};
use crate::value::Json;

const TYPES: [&str; 8] = ["boards", "todos", "docs", "chat", "files", "mail", "calendar", "room"];

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "tool list",
            "List your tools (* = new activity since you last looked)",
            &[],
            vec![flag("type", "TYPE", format!("Only tools of this type: {}", TYPES.join(", ")))],
            list,
        ),
        command("tool show", "Show a tool, your role and its collaborators", &["TOOL"], vec![], show),
        command(
            "tool create",
            "Create a tool (mail and calendar still need their account connected in the browser)",
            &["TYPE", "NAME"],
            vec![],
            create,
        ),
        command("tool rename", "Rename a tool (owners only)", &["TOOL", "NAME"], vec![], rename),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let mut tools = ctx.get("/tools", &[])?.items().to_vec();
    if let Some(kind) = args.flag("type") {
        tools.retain(|tool| tool["type"].s() == kind);
    }

    ctx.output(&json!(tools), |ctx| {
        if tools.is_empty() {
            ctx.say("No tools.");
        }
        tools.sort_by_key(|tool| (tool["type"].s(), tool["name"].s().to_lowercase()));
        let rows = tools
            .iter()
            .map(|tool| {
                let unread = if tool["unread"].truthy() { " *" } else { "" };
                vec![tool["id"].s(), tool["type"].s(), format!("{}{unread}", tool["name"].s())]
            })
            .collect();
        ctx.table(rows, 0);
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), None)?;
    let details = ctx.get(&format!("/tools/{}", tool["id"].s()), &[])?;

    ctx.output(&details, |ctx| {
        ctx.say(format!("{} ({} {})", details["name"].s(), details["type"].s(), details["id"].s()));
        ctx.field("Your role", details["role"].s());
        ctx.field("URL", details["url"].s());
        ctx.blank();
        ctx.say("Collaborators:");
        let rows = details["collaborators"]
            .items()
            .iter()
            .map(|user| vec![user["id"].s(), person(user).unwrap_or_default(), user["role"].s()])
            .collect();
        ctx.table(rows, 2);
        Ok(())
    })
}

fn create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (kind, name) = (args.at(0), args.at(1));
    if !TYPES.contains(&kind) {
        usage!("TYPE must be one of: {}", TYPES.join(", "));
    }

    let created = ctx.post("/tools", json!({ "tool": { "name": name, "tool_type": kind } }))?;
    ctx.output(&created, |ctx| {
        ctx.say(format!(
            "Created {} tool {} ({}): {}",
            created["type"].s(),
            quoted(&created["name"].s()),
            created["id"].s(),
            created["url"].s()
        ));
        Ok(())
    })
}

fn rename(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), None)?;
    let updated = ctx.patch(&format!("/tools/{}", tool["id"].s()), json!({ "tool": { "name": args.at(1) } }))?;
    ctx.output(&updated, |ctx| {
        ctx.say(format!("Renamed tool {} to {}.", updated["id"].s(), quoted(&updated["name"].s())));
        Ok(())
    })
}

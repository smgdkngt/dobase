use serde_json::{Map, Value, json};

use crate::command::{Args, Ctx, Definition, Flag, Result, command, flag, moment, quoted, switch, usage};
use crate::value::{Json, join};

fn content_flags() -> Vec<Flag> {
    vec![flag("content", "TEXT", "Content (plain text, or HTML with --html)"), switch("html", "The content is HTML")]
}

pub fn definitions() -> Vec<Definition> {
    vec![
        command("doc list", "List the documents in a docs tool, last edited first", &["TOOL"], vec![], list),
        command(
            "doc show",
            "Show a document with its content",
            &["TOOL/DOC"],
            vec![switch("html", "Print the content as HTML instead of plain text")],
            show,
        ),
        command("doc create", "Create a document", &["TOOL", "TITLE"], content_flags(), create),
        command(
            "doc update",
            "Rename a document or replace its content (refused while someone else is editing it)",
            &["TOOL/DOC"],
            [vec![flag("title", "TEXT", "New title")], content_flags()].concat(),
            update,
        ),
        command("doc delete", "Delete a document permanently", &["TOOL/DOC"], vec![], delete),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("docs"))?;
    let docs = ctx.get(&format!("/tools/{}/docs", tool["id"].s()), &[])?;

    ctx.output(&docs, |ctx| {
        ctx.say(format!("{} (docs {}) {}", tool["name"].s(), tool["id"].s(), docs["url"].s()));
        ctx.blank();
        let documents = docs["documents"].items();
        if documents.is_empty() {
            ctx.say("  (no documents)");
        }
        let rows = documents
            .iter()
            .map(|document| vec![format!("{}/{}", tool["id"].s(), document["id"].s()), document["title"].s(), document_summary(document)])
            .collect();
        ctx.table(rows, 2);
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "docs", "doc")?;
    let document = ctx.get(&format!("/tools/{}/docs/documents/{id}", tool["id"].s()), &[])?;

    ctx.output(&document, |ctx| {
        ctx.say(format!("{} (doc {}/{})", document["title"].s(), tool["id"].s(), document["id"].s()));
        ctx.field("Docs", tool["name"].s());
        ctx.field(
            "Editing",
            document["locked"].truthy().then(|| format!("{} has it open in the editor", document["locked_by"]["name"].s())),
        );
        ctx.field("Created", join([moment(&document["created_at"]), document["creator"]["name"].opt()], " by "));
        ctx.field("Updated", join([moment(&document["updated_at"]), document["updated_by"]["name"].opt()], " by "));
        ctx.field("URL", document["url"].s());
        ctx.blank();

        let content = if args.on("html") { document["content_html"].s() } else { document["content"].s() };
        ctx.say(if content.trim().is_empty() { "(empty)".to_string() } else { content });
        Ok(())
    })
}

fn create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("docs"))?;
    let mut attributes = Map::new();
    attributes.insert("title".into(), json!(args.at(1)));
    if let Some(content) = args.flag("content") {
        attributes.insert("content".into(), json!(ctx.rich_text(content, args.on("html"))?));
    }

    let document = ctx.post(&format!("/tools/{}/docs/documents", tool["id"].s()), json!({ "docs_document": attributes }))?;
    ctx.output(&document, |ctx| {
        ctx.say(format!(
            "Created doc {}/{} {}: {}",
            tool["id"].s(),
            document["id"].s(),
            quoted(&document["title"].s()),
            document["url"].s()
        ));
        Ok(())
    })
}

fn update(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "docs", "doc")?;
    let mut attributes = Map::new();
    if let Some(title) = args.flag("title") {
        attributes.insert("title".into(), json!(title));
    }
    if let Some(content) = args.flag("content") {
        attributes.insert("content".into(), json!(ctx.rich_text(content, args.on("html"))?));
    }
    if attributes.is_empty() {
        usage!("Nothing to update. See `dobase help doc`.");
    }

    let document = ctx.patch(&format!("/tools/{}/docs/documents/{id}", tool["id"].s()), json!({ "docs_document": attributes }))?;
    ctx.output(&document, |ctx| {
        ctx.say(format!("Updated doc {}/{} {}.", tool["id"].s(), document["id"].s(), quoted(&document["title"].s())));
        Ok(())
    })
}

fn delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "docs", "doc")?;
    ctx.delete(&format!("/tools/{}/docs/documents/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted doc {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn document_summary(document: &Value) -> String {
    join(
        [
            Some(join([moment(&document["updated_at"]).map(|at| format!("edited {at}")), document["updated_by"]["name"].opt()], " by ")),
            document["locked"].truthy().then(|| format!("{} is editing", document["locked_by"]["name"].s())),
        ],
        "  ",
    )
}

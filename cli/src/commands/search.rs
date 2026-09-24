use crate::command::{Args, Ctx, Definition, Result, command, usage};
use crate::value::Json;

pub fn definitions() -> Vec<Definition> {
    vec![command("search", "Find cards, todos, documents, files, messages, events and mail that match", &["QUERY..."], vec![], search)]
}

fn search(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let query = args.rest(0).join(" ").trim().to_string();
    if query.chars().count() < 2 {
        usage!("Give at least two characters to search for.");
    }

    let result = ctx.get("/search", &[("q", Some(query.clone()))])?;
    ctx.output(&result, |ctx| {
        let results = result["results"].items();
        if results.is_empty() {
            ctx.say(format!("Nothing matches \"{query}\"."));
        }
        let rows = results.iter().map(|hit| vec![hit["kind"].s(), hit["title"].s(), hit["tool_name"].s(), hit["url"].s()]).collect();
        ctx.table(rows, 0);
        Ok(())
    })
}

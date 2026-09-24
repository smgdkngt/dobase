use serde_json::json;

use crate::command::{Args, Ctx, Definition, Result, command, count, flag, moment, quoted, switch, usage};
use crate::value::{Json, is_digits};

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "notification list",
            "List your notifications, newest first (* = unread)",
            &[],
            vec![switch("unread", "Only unread notifications"), flag("limit", "N", "Number of notifications (default 20, max 100)")],
            list,
        ),
        command(
            "notification read",
            "Mark a notification as read, or all of them with --all",
            &["[ID]"],
            vec![switch("all", "Mark every notification as read")],
            read,
        ),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let unread = args.on("unread");
    let notifications =
        ctx.get("/notifications", &[("unread", unread.then(|| "true".to_string())), ("limit", args.flag("limit").map(str::to_string))])?;

    ctx.output(&notifications, |ctx| {
        let items = notifications.items();
        if items.is_empty() {
            ctx.say(if unread { "No unread notifications." } else { "No notifications." });
        }
        let rows = items
            .iter()
            .map(|notification| {
                vec![
                    if notification["read"].truthy() { String::new() } else { "*".to_string() },
                    notification["id"].s(),
                    moment(&notification["created_at"]).unwrap_or_default(),
                    notification["message"].s(),
                    notification["url"].s(),
                ]
            })
            .collect();
        ctx.table(rows, 0);
        Ok(())
    })
}

fn read(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (id, all) = (args.get(0), args.on("all"));
    if id.is_some() && all {
        usage!("Give a notification ID or --all, not both.");
    }

    match id {
        None if !all => usage!("Give a notification ID or --all. `dobase notification list` shows the ids."),
        None => {
            let result = ctx.post("/notification_reads", json!({}))?;
            ctx.output(&result, |ctx| {
                ctx.say(format!("Marked {} as read.", count(result["marked_as_read"].int(), "notification")));
                Ok(())
            })
        }
        Some(id) => {
            if !is_digits(id) {
                usage!("Expected a notification id like 41, got {}.", quoted(id));
            }
            let notification = ctx.post(&format!("/notifications/{id}/read"), json!({}))?;
            ctx.output(&notification, |ctx| {
                ctx.say(format!("Marked notification {} as read: {}", notification["id"].s(), notification["message"].s()));
                Ok(())
            })
        }
    }
}

use std::time::{Duration, Instant};

use jiff::SignedDuration;
use jiff::civil::{Date, DateTime};
use serde_json::{Map, Value, json};

use super::boards::find_named;
use crate::command::{
    Args, Ctx, Definition, Error, Flag, Result, command, date_param, fail, flag, moment, person, quoted, switch, today, usage,
};
use crate::value::{Json, join};

const FREQUENCIES: [&str; 4] = ["daily", "weekly", "monthly", "yearly"];
const SYNC_TIMEOUT: Duration = Duration::from_secs(60);

fn event_flags(updating: bool) -> Vec<Flag> {
    let mut flags = vec![
        flag("start", "TIME", "Start: \"YYYY-MM-DD HH:MM\" in your Dobase time zone (a date with --all-day)"),
        if updating {
            flag("end", "TIME", "New end, like --start (a new --start alone keeps the length)")
        } else {
            flag("end", "TIME", "End, like --start (default: --duration after the start)")
        },
        if updating {
            flag("duration", "DURATION", "New length instead of --end: 30m, 1h, 1h30m")
        } else {
            flag("duration", "DURATION", "Length instead of --end: 30m, 1h, 1h30m (default 1h)")
        },
        switch("all-day", "All-day event: --start and --end are dates (--end defaults to --start)"),
        flag("location", "TEXT", "Location"),
        flag("description", "TEXT", "Description (plain text)"),
        if updating {
            flag("calendar", "CALENDAR", "Move to this calendar (id or name)")
        } else {
            flag("calendar", "CALENDAR", "Calendar id or name (default: the default calendar)")
        },
        flag("repeat", "FREQUENCY", format!("Repeat {}, or none to stop repeating", FREQUENCIES.join(", "))),
        flag("repeat-until", "DATE", "Repeat until this date (YYYY-MM-DD)"),
        flag("repeat-count", "N", "Repeat N times"),
    ];
    if updating {
        flags.push(flag("title", "TEXT", "New title"));
    }
    flags
}

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "event list",
            "List events by day: today and the next 6 days, unless you pick the days",
            &["TOOL"],
            vec![
                flag("from", "DATE", "First day: YYYY-MM-DD, today or tomorrow (default: today)"),
                flag("to", "DATE", "Last day, included"),
                flag("days", "N", "Number of days, instead of --to"),
            ],
            list,
        ),
        command("event show", "Show an event; a repeating event shows as its whole series", &["TOOL/EVENT"], vec![], show),
        command("event create", "Add an event to a calendar tool", &["TOOL", "TITLE"], event_flags(false), create),
        command(
            "event update",
            "Change an event; for a repeating event this changes the whole series",
            &["TOOL/EVENT"],
            event_flags(true),
            update,
        ),
        command("event delete", "Delete an event; for a repeating event, every occurrence", &["TOOL/EVENT"], vec![], delete),
        command("calendar list", "List the calendars of a calendar tool and its sync status", &["TOOL"], vec![], calendar_list),
        command(
            "calendar sync",
            "Sync a calendar tool with its CalDAV server and wait up to a minute for it",
            &["TOOL"],
            vec![],
            calendar_sync,
        ),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (from, to, days) = (args.flag("from"), args.flag("to"), args.flag("days"));
    if to.is_some() && days.is_some() {
        usage!("Use --to or --days, not both.");
    }

    let tool = ctx.tool(args.at(0), Some("calendar"))?;
    let mut first_day = from.map(day_param).transpose()?;
    let mut last_day = to.map(day_param).transpose()?;
    if let Some(days) = days {
        let first = *first_day.get_or_insert_with(today);
        last_day = Some(add_days(first, positive_integer(days, "--days")? - 1));
    }

    let agenda = ctx.get(
        &format!("/tools/{}/calendar", tool["id"].s()),
        &[("start_date", first_day.map(|day| day.to_string())), ("end_date", last_day.map(|day| day.to_string()))],
    )?;

    ctx.output(&agenda, |ctx| {
        let first_day = date_of(&agenda["start_date"]);
        ctx.say(format!(
            "{} (calendar {}): {} to {}",
            tool["name"].s(),
            tool["id"].s(),
            full_day(first_day),
            full_day(date_of(&agenda["end_date"]))
        ));
        let events = agenda["events"].items();
        if events.is_empty() {
            ctx.say("  (no events)");
        }

        // Events that began before the first day are listed under it.
        let mut days: Vec<(Date, Vec<(usize, &Value)>)> = Vec::new();
        for (index, event) in events.iter().enumerate() {
            let listed_on = date_of(&event["starts_at"]).max(first_day);
            match days.iter_mut().find(|(day, _)| *day == listed_on) {
                Some((_, entries)) => entries.push((index, event)),
                None => days.push((listed_on, vec![(index, event)])),
            }
        }

        for (listed_on, mut entries) in days {
            ctx.blank();
            ctx.say(listed_on.strftime("%A %-d %B %Y").to_string());
            entries.sort_by_key(|(index, event)| (!event["all_day"].truthy(), *index));
            let rows = entries
                .iter()
                .map(|(_, event)| {
                    vec![
                        time_range(event, listed_on),
                        format!("{}/{}", tool["id"].s(), event["id"].s()),
                        event["summary"].s(),
                        event_details(event),
                    ]
                })
                .collect();
            ctx.table(rows, 2);
        }
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "calendar", "event")?;
    let event = ctx.get(&format!("/tools/{}/calendar/events/{id}", tool["id"].s()), &[])?;

    ctx.output(&event, |ctx| {
        ctx.say(format!("{} (event {}/{})", event["summary"].s(), tool["id"].s(), event["id"].s()));
        ctx.field("When", event_span(&event));
        ctx.field("Repeats", event["recurrence"].s());
        ctx.field("Calendar", event["calendar"]["name"].s());
        ctx.field("Location", event["location"].s());
        ctx.field("Status", event["status"].s());
        ctx.field("Organizer", organizer(&event["organizer"]));
        ctx.field("Created by", person(&event["creator"]));
        ctx.field("URL", event["url"].s());

        let description = event["description"].s();
        if !description.trim().is_empty() {
            ctx.blank();
            ctx.say("Description:");
            ctx.paragraph(&description, 2);
        }

        let attendees = event["attendees"].items();
        if !attendees.is_empty() {
            ctx.blank();
            ctx.say(format!("Attendees ({}):", attendees.len()));
            let rows = attendees.iter().map(|attendee| vec![organizer(attendee).unwrap_or_default(), attendee["status"].s()]).collect();
            ctx.table(rows, 2);
        }
        Ok(())
    })
}

fn create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    if args.flag("start").is_none() {
        usage!("--start is required. See `dobase help event`.");
    }

    let tool = ctx.tool(args.at(0), Some("calendar"))?;
    let mut attributes = event_attributes(ctx, &tool, args, None, true)?;
    attributes.insert("summary".into(), json!(args.at(1)));
    let event = ctx.post(&format!("/tools/{}/calendar/events", tool["id"].s()), json!({ "calendars_event": attributes }))?;

    ctx.output(&event, |ctx| {
        ctx.say(format!(
            "Created event {}/{} {} in {}: {}",
            tool["id"].s(),
            event["id"].s(),
            quoted(&event["summary"].s()),
            event["calendar"]["name"].s(),
            event_span(&event)
        ));
        ctx.field("Repeats", event["recurrence"].s());
        Ok(())
    })
}

fn update(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "calendar", "event")?;
    let path = format!("/tools/{}/calendar/events/{id}", tool["id"].s());

    let changes_timing = args.any(&["start", "end", "duration", "all-day"]);
    let changes_repeat_end = args.any(&["repeat-until", "repeat-count"]) && args.flag("repeat").is_none();
    let current = if changes_timing || changes_repeat_end { Some(ctx.get(&path, &[])?) } else { None };
    if changes_repeat_end && !current.as_ref().is_some_and(|event| event["recurring"].truthy()) {
        usage!("Event {}/{id} doesn't repeat. Add --repeat FREQUENCY.", tool["id"].s());
    }

    let mut attributes = event_attributes(ctx, &tool, args, current.as_ref(), false)?;
    if let Some(title) = args.flag("title") {
        attributes.insert("summary".into(), json!(title));
    }
    if attributes.is_empty() {
        usage!("Nothing to update. See `dobase help event`.");
    }

    let event = ctx.patch(&path, json!({ "calendars_event": attributes }))?;
    ctx.output(&event, |ctx| {
        ctx.say(format!(
            "Updated event {}/{} {} in {}: {}",
            tool["id"].s(),
            event["id"].s(),
            quoted(&event["summary"].s()),
            event["calendar"]["name"].s(),
            event_span(&event)
        ));
        ctx.field("Repeats", event["recurrence"].s());
        Ok(())
    })
}

fn delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "calendar", "event")?;
    ctx.delete(&format!("/tools/{}/calendar/events/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted event {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn calendar_list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("calendar"))?;
    let overview = calendar_overview(ctx, &tool)?;

    ctx.output(&overview, |ctx| {
        ctx.say(format!("{} (calendar {})", tool["name"].s(), tool["id"].s()));
        ctx.field("Sync", sync_summary(&overview));
        ctx.blank();
        let rows = overview["calendars"]
            .items()
            .iter()
            .map(|calendar| vec![calendar["id"].s(), calendar["name"].s(), calendar["color"].s(), calendar_flags(calendar)])
            .collect();
        ctx.table(rows, 2);
        Ok(())
    })
}

fn calendar_sync(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("calendar"))?;
    let path = format!("/tools/{}/calendar/sync", tool["id"].s());

    let mut status = ctx.post(&path, json!({}))?;
    let deadline = Instant::now() + SYNC_TIMEOUT;
    while status["status"].s() == "syncing" && Instant::now() < deadline {
        std::thread::sleep(Duration::from_secs(1));
        status = ctx.get(&path, &[])?;
    }

    ctx.output(&status, |ctx| {
        let name = format!("{} (calendar {})", tool["name"].s(), tool["id"].s());
        match status["status"].s().as_str() {
            "synced" => ctx.say(format!("Synced {name} at {}.", moment(&status["last_synced_at"]).unwrap_or_default())),
            "syncing" => ctx.say(format!("{name} is still syncing. Check later with `dobase calendar list {}`.", tool["id"].s())),
            _ => fail!("Syncing {name} failed. Check its calendar account in the browser."),
        }
        Ok(())
    })
}

/// The calendar for a single day: enough for its calendars and sync status.
fn calendar_overview(ctx: &mut Ctx, tool: &Value) -> Result<Value> {
    let today = today().to_string();
    ctx.get(&format!("/tools/{}/calendar", tool["id"].s()), &[("start_date", Some(today.clone())), ("end_date", Some(today))])
}

// -- Input -------------------------------------------------------------------

fn event_attributes(ctx: &mut Ctx, tool: &Value, args: &Args, current: Option<&Value>, creating: bool) -> Result<Map<String, Value>> {
    let mut attributes = timing_attributes(args, current)?;
    if let Some(location) = args.flag("location") {
        attributes.insert("location".into(), json!(ctx.text(location)?));
    }
    if let Some(description) = args.flag("description") {
        attributes.insert("description".into(), json!(ctx.text(description)?.trim_end()));
    }
    if let Some(calendar) = args.flag("calendar") {
        let calendars = calendar_overview(ctx, tool)?;
        let found = find_named(calendars["calendars"].items(), Some(calendar), "name", "calendar", "Calendars", &tool["name"].s())?;
        attributes.insert("calendar_id".into(), found["id"].clone());
    }
    attributes.extend(recurrence_attributes(args, creating)?);
    Ok(attributes)
}

/// A --start or --end value: its date, and its time unless it was a date alone.
struct When {
    flag: &'static str,
    date: Date,
    time: Option<(i8, i8)>,
}

/// start_time, end_time and all_day from --start, --end, --duration and --all-day.
/// When updating, `current` is the event: what isn't given stays as it is, and
/// a new start keeps the event's length.
fn timing_attributes(args: &Args, current: Option<&Value>) -> Result<Map<String, Value>> {
    if !args.any(&["start", "end", "duration", "all-day"]) {
        return Ok(Map::new());
    }
    if args.flag("end").is_some() && args.flag("duration").is_some() {
        usage!("Use --end or --duration, not both.");
    }

    let start = args.flag("start").map(|value| time_param(value, "--start")).transpose()?;
    let finish = args.flag("end").map(|value| time_param(value, "--end")).transpose()?;
    let stays_all_day =
        current.is_some_and(|event| event["all_day"].truthy()) && [&start, &finish].into_iter().flatten().all(|when| when.time.is_none());

    if args.on("all-day") || stays_all_day {
        all_day_timing(start, finish, args, current)
    } else {
        timed_timing(start, finish, args, current)
    }
}

/// All-day events run from the start of the first day to the end of the last.
fn all_day_timing(start: Option<When>, finish: Option<When>, args: &Args, current: Option<&Value>) -> Result<Map<String, Value>> {
    if args.flag("duration").is_some() {
        usage!("--duration doesn't work for all-day events. Use --end DATE.");
    }
    let current_all_day = current.is_some_and(|event| event["all_day"].truthy());

    let first = match (&start, current) {
        (Some(start), _) => start.date,
        (None, Some(event)) => date_of(&event["starts_at"]),
        (None, None) => usage!("--start is required. See `dobase help event`."),
    };
    let last = match (&finish, &start, current) {
        (Some(finish), _, _) => finish.date,
        (None, Some(_), Some(event)) if current_all_day => {
            add_days(first, days_between(date_of(&event["starts_at"]), date_of(&event["ends_at"])))
        }
        (None, Some(_), _) => first,
        (None, None, Some(event)) => date_of(&event["ends_at"]).max(first),
        (None, None, None) => first,
    };
    if last < first {
        usage!("--end is before the start.");
    }

    let mut attributes = Map::new();
    attributes.insert("all_day".into(), json!(true));
    attributes.insert("end_time".into(), json!(format!("{last} 23:59:59")));
    if start.is_some() || !current_all_day {
        attributes.insert("start_time".into(), json!(format!("{first} 00:00")));
    }
    Ok(attributes)
}

fn timed_timing(start: Option<When>, finish: Option<When>, args: &Args, current: Option<&Value>) -> Result<Map<String, Value>> {
    for when in [&start, &finish].into_iter().flatten() {
        if when.time.is_none() {
            usage!("{} needs a time, like \"2026-10-01 14:30\", or add --all-day.", when.flag);
        }
    }
    let current_timed = current.filter(|event| !event["all_day"].truthy());

    let starts = match (&start, current) {
        (Some(start), _) => wall_clock(start),
        (None, Some(event)) => wall_clock_of(&event["starts_at"])?,
        (None, None) => usage!("--start is required. See `dobase help event`."),
    };
    let ends = if let Some(finish) = &finish {
        wall_clock(finish)
    } else if let Some(duration) = args.flag("duration") {
        starts + duration_param(duration)?
    } else if let Some(event) = current_timed {
        starts + wall_clock_of(&event["ends_at"])?.duration_since(wall_clock_of(&event["starts_at"])?)
    } else {
        starts + SignedDuration::from_hours(1)
    };
    if ends < starts {
        usage!("--end is before the start.");
    }

    let mut attributes = Map::new();
    attributes.insert("all_day".into(), json!(false));
    attributes.insert("end_time".into(), json!(clock_param(ends)));
    if start.is_some() || current.is_none() || current.is_some_and(|event| event["all_day"].truthy()) {
        attributes.insert("start_time".into(), json!(clock_param(starts)));
    }
    Ok(attributes)
}

fn recurrence_attributes(args: &Args, creating: bool) -> Result<Map<String, Value>> {
    let (repeat, until, count) = (args.flag("repeat"), args.flag("repeat-until"), args.flag("repeat-count"));
    let mut attributes = Map::new();
    if repeat.is_none() && until.is_none() && count.is_none() {
        return Ok(attributes);
    }

    if until.is_some() && count.is_some() {
        usage!("Use --repeat-until or --repeat-count, not both.");
    }
    if let Some(repeat) = repeat
        && !FREQUENCIES.contains(&repeat)
        && repeat != "none"
    {
        usage!("--repeat must be one of: {}, none", FREQUENCIES.join(", "));
    }
    if repeat == Some("none") && (until.is_some() || count.is_some()) {
        usage!("--repeat none can't have --repeat-until or --repeat-count.");
    }
    if creating && repeat.is_none() {
        usage!("--repeat-until and --repeat-count need --repeat.");
    }

    if let Some(repeat) = repeat {
        attributes.insert("recurrence_frequency".into(), json!(repeat));
    }
    if let Some(until) = until {
        attributes.insert("recurrence_end_type".into(), json!("until"));
        attributes.insert("recurrence_until".into(), json!(day_param(until)?.to_string()));
    } else if let Some(count) = count {
        attributes.insert("recurrence_end_type".into(), json!("count"));
        attributes.insert("recurrence_count".into(), json!(positive_integer(count, "--repeat-count")?));
    } else if repeat != Some("none") {
        attributes.insert("recurrence_end_type".into(), json!("never"));
    }
    Ok(attributes)
}

/// "YYYY-MM-DD HH:MM" or a date alone; today and tomorrow work too.
fn time_param(value: &str, flag: &'static str) -> Result<When> {
    let invalid = || Error::usage(format!("{flag} expects \"YYYY-MM-DD HH:MM\", got {}.", quoted(value)));
    let trimmed = value.trim();
    let (day, time) = match trimmed.split_once([' ', 'T']) {
        Some((day, time)) => (day, Some(time)),
        None => (trimmed, None),
    };
    let day_ok = day == "today" || day == "tomorrow" || (day.len() == 10 && day.chars().all(|char| char.is_ascii_digit() || char == '-'));
    if !day_ok {
        return Err(invalid());
    }

    let time = match time {
        None => None,
        Some(time) => {
            let (hours, minutes) = time.split_once(':').ok_or_else(invalid)?;
            let digits = |text: &str| !text.is_empty() && text.chars().all(|char| char.is_ascii_digit());
            if !(digits(hours) && hours.len() <= 2 && digits(minutes) && minutes.len() == 2) {
                return Err(invalid());
            }
            let (hours, minutes): (i8, i8) = (hours.parse().unwrap(), minutes.parse().unwrap());
            if hours > 23 || minutes > 59 {
                usage!("{flag} has an invalid time: {}.", quoted(value));
            }
            Some((hours, minutes))
        }
    };
    Ok(When { flag, date: day_param(day)?, time })
}

fn day_param(value: &str) -> Result<Date> {
    match date_param(value) {
        Ok(Some(date)) => Ok(date.parse().unwrap()),
        _ => usage!("Expected a date like 2026-10-01, today or tomorrow; got {}.", quoted(value)),
    }
}

/// "30m", "1h" or "1h30m".
fn duration_param(value: &str) -> Result<SignedDuration> {
    let text = value.trim().to_lowercase();
    let (hours, rest) = match text.split_once('h') {
        Some((hours, rest)) => (hours, rest),
        None => ("", text.as_str()),
    };
    let minutes = rest.strip_suffix('m').unwrap_or(rest);
    let valid = (hours.is_empty() || hours.chars().all(|char| char.is_ascii_digit()))
        && (minutes.is_empty() || (rest.ends_with('m') && minutes.chars().all(|char| char.is_ascii_digit())))
        && !(text.contains('h') && hours.is_empty());
    let seconds = if valid { hours.parse::<i64>().unwrap_or(0) * 3600 + minutes.parse::<i64>().unwrap_or(0) * 60 } else { 0 };
    if seconds <= 0 {
        usage!("--duration expects a length like 30m, 1h or 1h30m, got {}.", quoted(value));
    }
    Ok(SignedDuration::from_secs(seconds))
}

fn positive_integer(value: &str, flag: &str) -> Result<i64> {
    match value.parse::<i64>() {
        Ok(number) if number > 0 => Ok(number),
        _ => usage!("{flag} expects a positive number, got {}.", quoted(value)),
    }
}

// Times are wall-clock times in the user's Dobase time zone, so they have no zone here.

fn wall_clock(when: &When) -> DateTime {
    let (hours, minutes) = when.time.unwrap_or((0, 0));
    when.date.at(hours, minutes, 0, 0)
}

fn wall_clock_of(timestamp: &Value) -> Result<DateTime> {
    let text: String = timestamp.s().chars().take(16).collect();
    text.parse().map_err(|_| Error::failed(format!("The server sent an odd time: {text}")))
}

fn clock_param(time: DateTime) -> String {
    time.strftime("%Y-%m-%d %H:%M").to_string()
}

fn add_days(date: Date, days: i64) -> Date {
    date.checked_add(jiff::Span::new().days(days)).unwrap_or(date)
}

fn days_between(from: Date, to: Date) -> i64 {
    from.until(to).map(|span| i64::from(span.get_days())).unwrap_or(0)
}

// -- Output ------------------------------------------------------------------

fn date_of(timestamp: &Value) -> Date {
    timestamp.s().chars().take(10).collect::<String>().parse().unwrap_or_else(|_| today())
}

fn clock(timestamp: &Value) -> String {
    timestamp.s().chars().skip(11).take(5).collect()
}

fn short_day(date: Date) -> String {
    date.strftime("%a %-d %b").to_string()
}

fn full_day(date: Date) -> String {
    date.strftime("%a %-d %b %Y").to_string()
}

fn event_span(event: &Value) -> String {
    let (starts_on, ends_on) = (date_of(&event["starts_at"]), date_of(&event["ends_at"]));
    let (starts, ends) = (clock(&event["starts_at"]), clock(&event["ends_at"]));

    if event["all_day"].truthy() {
        if ends_on > starts_on {
            format!("{} to {}, all day", full_day(starts_on), full_day(ends_on))
        } else {
            format!("{}, all day", full_day(starts_on))
        }
    } else if ends_on == starts_on {
        format!("{} {starts}–{ends}", full_day(starts_on))
    } else {
        format!("{} {starts} to {} {ends}", full_day(starts_on), full_day(ends_on))
    }
}

/// The time of an event listed under `listed_on`.
fn time_range(event: &Value, listed_on: Date) -> String {
    let (starts_on, ends_on) = (date_of(&event["starts_at"]), date_of(&event["ends_at"]));

    if event["all_day"].truthy() {
        if ends_on > listed_on { format!("all day until {}", short_day(ends_on)) } else { "all day".to_string() }
    } else {
        let from = if starts_on == listed_on {
            clock(&event["starts_at"])
        } else {
            format!("{} {}", short_day(starts_on), clock(&event["starts_at"]))
        };
        let till =
            if ends_on == starts_on { clock(&event["ends_at"]) } else { format!("{} {}", short_day(ends_on), clock(&event["ends_at"])) };
        format!("{from}–{till}")
    }
}

fn event_details(event: &Value) -> String {
    let status = event["status"].s();
    join(
        [
            event["calendar"]["name"].opt(),
            event["location"].opt(),
            event["recurring"].truthy().then(|| "repeats".to_string()),
            ["tentative", "cancelled"].contains(&status.as_str()).then_some(status),
        ],
        " · ",
    )
}

fn organizer(contact: &Value) -> Option<String> {
    (!contact.is_null()).then(|| join([contact["name"].opt(), contact["email"].opt().map(|email| format!("<{email}>"))], " "))
}

fn sync_summary(overview: &Value) -> String {
    if overview["local"].truthy() {
        return "none, events are kept in Dobase".to_string();
    }
    format!(
        "{}, last synced {}",
        overview["sync"]["status"].s(),
        moment(&overview["sync"]["last_synced_at"]).unwrap_or_else(|| "never".to_string())
    )
}

fn calendar_flags(calendar: &Value) -> String {
    join(
        [
            calendar["is_default"].truthy().then(|| "default".to_string()),
            calendar["read_only"].truthy().then(|| "read-only".to_string()),
            (!calendar["enabled"].truthy()).then(|| "disabled".to_string()),
        ],
        ", ",
    )
}

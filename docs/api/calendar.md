# Calendar

A calendar tool has one account with one or more calendars. The account either
keeps its events in Dobase (`local`) or syncs them with a CalDAV server such as
Fastmail, iCloud or Nextcloud. Connecting and changing the account happens in the
browser; tokens can't reach it. Changes you make through the API are sent to the
CalDAV server in the background.

Every calendar endpoint answers `404` with
`{"error": "Calendar account not configured"}` when the tool has no account yet.

## Calendar

`GET /tools/:tool_id/calendar` returns the calendars in the account and the
events from `start_date` through `end_date` (`YYYY-MM-DD`, both included).
Without them you get today and the six days after it, and `end_date` defaults to
six days after `start_date`. The range can be 92 days at most. A longer range, an
`end_date` before `start_date` or a malformed date answers `422` with
`{"error": "..."}`.

```json
{
  "tool": { "id": 9, "name": "Calendar", "type": "calendar", "url": "...", "created_at": "...", "updated_at": "..." },
  "url": "https://dobase.example.com/tools/9/calendar?week_start=2026-09-14",
  "local": true,
  "sync": { "status": "synced", "last_synced_at": "2026-09-14T17:55:53.649+02:00" },
  "start_date": "2026-09-16",
  "end_date": "2026-09-17",
  "calendars": [
    { "id": 1, "name": "Moonshot Calendar", "color": "#ff6b35", "is_default": true, "enabled": true, "read_only": false, "writable": true },
    { "id": 3, "name": "Holidays", "color": "#9ca3af", "is_default": false, "enabled": true, "read_only": true, "writable": false }
  ],
  "events": [
    {
      "id": 19,
      "summary": "Standup",
      "description": null,
      "location": null,
      "starts_at": "2026-09-16T10:00:00.000+02:00",
      "ends_at": "2026-09-16T10:15:00.000+02:00",
      "all_day": false,
      "status": "confirmed",
      "calendar": { "id": 1, "name": "Moonshot Calendar", "color": "#ff6b35" },
      "recurring": true,
      "occurrence": true,
      "recurrence": "Weekly, 3 times",
      "rrule": "FREQ=WEEKLY;COUNT=3",
      "organizer": null,
      "attendees": [],
      "creator": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
      "url": "https://dobase.example.com/tools/9/calendar?week_start=2026-09-14"
    }
  ]
}
```

- `local` is true when the events live only in Dobase. `sync.status` is
  `pending`, `syncing`, `synced` or `error`.
- `writable` calendars take new events: they are `enabled` and not `read_only`.
  Dobase marks a calendar read-only when its server refuses a change.
- Events are listed in start order, from enabled calendars only. An event that
  began before `start_date` and is still going is included.
- A repeating event is listed once for every occurrence that starts in the
  range. Each occurrence has `occurrence: true`, its own `starts_at` and
  `ends_at`, and the `id` of the series, which is what you show, update or
  delete. `recurrence` describes the rule in words and `rrule` is the iCalendar
  rule.
- `status` is `confirmed`, `tentative` or `cancelled`, or `null` when a synced
  event has none.
- `url` opens the week of the event in the browser.

## Events

### Show

`GET /tools/:tool_id/calendar/events/:id` returns one event with the fields
above. For a repeating event you get the series: `starts_at` and `ends_at` are
its first occurrence and `occurrence` is false. Invites synced from a CalDAV
server carry an `organizer` and `attendees`, whose `status` is their reply
(`accepted`, `declined`, `tentative` or `needs-action`):

```json
{
  "id": 9,
  "summary": "Investor Follow-up — North Star Ventures",
  "description": "Follow-up meeting with Rachel Kim to discuss seed round terms",
  "location": "Zoom",
  "starts_at": "2026-09-17T16:00:00.000+02:00",
  "ends_at": "2026-09-17T17:00:00.000+02:00",
  "all_day": false,
  "status": "confirmed",
  "calendar": { "id": 1, "name": "Moonshot Calendar", "color": "#ff6b35" },
  "recurring": false,
  "occurrence": false,
  "recurrence": null,
  "rrule": null,
  "organizer": { "name": "Rachel Kim", "email": "rachel@northstar.vc" },
  "attendees": [
    { "name": "Rachel Kim", "email": "rachel@northstar.vc", "status": "accepted" },
    { "name": "Sophie Chen", "email": "sophie@moonshot-snacks.com", "status": "needs-action" }
  ],
  "creator": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
  "url": "https://dobase.example.com/tools/9/calendar?week_start=2026-09-14"
}
```

### Create

`POST /tools/:tool_id/calendar/events` with:

```json
{ "calendars_event": { "summary": "Flavor lab", "calendar_id": 2, "location": "CloudKitchens Downtown, Unit 12", "start_time": "2026-09-18 14:00", "end_time": "2026-09-18 15:30" } }
```

`summary`, `start_time` and `end_time` are required. Times are read in your time
zone (`2026-09-18 14:00`), unless they carry an offset
(`2026-09-18T14:00:00+02:00`). The other fields are `description` and `location`
(plain text), `all_day` (`true` or `false`) and `status`. For an all-day event,
send the start of its first day and the end of its last, e.g. `2026-10-05 00:00`
and `2026-10-06 23:59:59`.

`calendar_id` defaults to the default calendar. A calendar that isn't in this
tool answers `404`, and a read-only or disabled one `422` with
`{"errors": ["Calendar is read-only"]}`.

Returns `201` and the event, sends it to the CalDAV server, and notifies the
tool's other collaborators.

### Repeating events

Add these fields to make an event repeat:

| Field | Values |
|-------|--------|
| `recurrence_frequency` | `daily`, `weekly`, `monthly` or `yearly` (`none` stops repeating) |
| `recurrence_interval` | Repeat every N days, weeks, months or years (default `1`) |
| `recurrence_days_of_week` | Weekly: days like `["MO", "FR"]` (default: the weekday of the start) |
| `recurrence_monthly_by` | Monthly: `day_of_month` (default, e.g. the 18th) or `day_of_week` (e.g. the 3rd Friday), taken from the start |
| `recurrence_end_type` | `never` (default), `count` or `until` |
| `recurrence_count` | With `count`: the number of occurrences |
| `recurrence_until` | With `until`: the last date, `YYYY-MM-DD` |

```json
{ "calendars_event": { "summary": "Flavor lab", "start_time": "2026-09-18 14:00", "end_time": "2026-09-18 15:30", "recurrence_frequency": "weekly", "recurrence_days_of_week": ["MO", "FR"], "recurrence_end_type": "until", "recurrence_until": "2026-10-31" } }
```

returns, among the other fields,
`"recurrence": "Weekly on Monday, Friday, until Oct 31, 2026"` and
`"rrule": "FREQ=WEEKLY;BYDAY=MO,FR;UNTIL=20261031T235959Z"`.

### Update

`PATCH /tools/:tool_id/calendar/events/:id` with any of the fields above under
`calendars_event` returns the event and sends the change to the server.
`calendar_id` moves the event to another calendar, with the same rules as
creating one.

A repeating event is one series, so an update always changes all of its
occurrences. You can't change or delete a single occurrence.

- A new `start_time` moves the series: the new start is its first occurrence,
  and the rule is rebuilt from it, as when you save the event in the browser.
  The weekdays you picked, the interval and the end stay; the rest follows the
  new start, such as the day a monthly event repeats on.
- On a repeating event, recurrence fields without `recurrence_frequency` change
  only those parts, e.g. `{"recurrence_end_type": "count", "recurrence_count": 5}`.
  With `recurrence_frequency` you set the whole rule, and the fields you leave
  out get their defaults.
- `{"recurrence_frequency": "none"}` turns the series into a single event at its
  first occurrence.
- Rules from other calendar apps that the browser's form can't express, like
  "the last Friday of the month", are simplified when you change the start or
  the recurrence. Changing other fields leaves the rule as it is.

### Delete

`DELETE /tools/:tool_id/calendar/events/:id` returns `204` and deletes the event
from the server too. For a repeating event that is every occurrence.

## Sync

Dobase syncs every CalDAV account every 15 minutes.
`POST /tools/:tool_id/calendar/sync` starts a sync right away and returns `201`:

```json
{ "status": "syncing", "last_synced_at": "2026-09-14T17:55:53+02:00" }
```

`GET /tools/:tool_id/calendar/sync` returns the same until `status` is `synced`
or `error`. A local account has nothing to fetch, so it is `synced` again as soon
as the background job has run.

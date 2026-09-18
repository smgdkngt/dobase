# Tools

## Who am I

`GET /profile`

```json
{
  "id": 1,
  "name": "Sophie Chen",
  "email_address": "sophie@moonshot-snacks.com",
  "first_name": "Sophie",
  "last_name": "Chen",
  "timezone": "Amsterdam",
  "access_token": { "name": "Claude", "permission": "write", "created_at": "2026-09-14T15:16:02.000+02:00" }
}
```

## List tools

`GET /tools` returns every tool you can access. `unread` is true when there is
activity you haven't seen in the browser yet.

```json
[
  {
    "id": 1,
    "name": "Product Launch",
    "type": "boards",
    "url": "https://dobase.example.com/tools/1",
    "created_at": "2026-09-14T15:16:02.000+02:00",
    "updated_at": "2026-09-14T15:16:02.000+02:00",
    "unread": true
  }
]
```

Types are `boards`, `todos`, `docs`, `chat`, `files`, `mail`, `calendar` and `room`.

## Show a tool

`GET /tools/:id` adds your `role` (`owner` or `collaborator`) and the people on
the tool. Use their ids to assign cards and todos.

```json
{
  "id": 1,
  "name": "Product Launch",
  "type": "boards",
  "url": "https://dobase.example.com/tools/1",
  "created_at": "2026-09-14T15:16:02.000+02:00",
  "updated_at": "2026-09-14T15:16:02.000+02:00",
  "role": "owner",
  "collaborators": [
    { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com", "role": "owner" }
  ]
}
```

## Create a tool

`POST /tools` with `{"tool": {"name": "Launch plan", "tool_type": "todos"}}`
returns `201` and the tool. Boards start with three columns, and todos start
with one list. Mail and calendar tools need their account connected in the
browser.

## Rename a tool

`PATCH /tools/:id` with `{"tool": {"name": "Roadmap"}}`. Owners only. A tool's
type is settled when it's created and can't be changed afterwards.

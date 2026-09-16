# Todos

## Lists and items

`GET /tools/:tool_id/todo` returns the lists in order, each with the items the
page shows: open items first, then the ones completed in the last 24 hours.
Add `?completed=true` to get every completed item instead.

```json
{
  "tool": { "id": 3, "name": "Launch Tasks", "type": "todos", "url": "...", "created_at": "...", "updated_at": "..." },
  "url": "https://dobase.example.com/tools/3/todo",
  "lists": [
    {
      "id": 1,
      "title": "Pre-Launch Checklist",
      "position": 0,
      "items": [
        {
          "id": 16,
          "title": "Book the launch party venue (50 people)",
          "due_date": "2026-09-14",
          "position": 2,
          "todo_list_id": 1,
          "completed": false,
          "completed_at": null,
          "recurrence_rule": "daily",
          "assignee": { "id": 3, "name": "Priya Patel", "email_address": "priya@moonshot-snacks.com" },
          "comments_count": 3,
          "attachments_count": 2,
          "url": "https://dobase.example.com/tools/3/todo?item=16",
          "created_at": "...",
          "updated_at": "..."
        }
      ]
    }
  ]
}
```

A completed item has `"completed": true` and `completed_at` set, e.g.
`"2026-09-13T15:38:46.459Z"`. `recurrence_rule` is `daily`, `weekly`,
`monthly` or `null`.

## Items

### Show

`GET /tools/:tool_id/todo/items/:id` returns the item fields above plus
`description`/`description_html`, `list`, `creator`, `comments` and
`attachments`:

```json
{
  "description": "Rooftop or the office?\n\nNeeds room for 50.",
  "description_html": "<p>Rooftop or the office?</p><p>Needs room for 50.</p>",
  "list": { "id": 1, "title": "Pre-Launch Checklist", "position": 0 },
  "creator": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
  "comments": [
    {
      "id": 2,
      "body": "Quote is €1,200",
      "body_html": "<p>Quote is <strong>€1,200</strong></p>",
      "user": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
      "created_at": "..."
    }
  ],
  "attachments": [
    { "id": 1, "filename": "venue-brief.txt", "content_type": "text/plain", "file_size": 51, "download_url": "...", "created_at": "..." }
  ]
}
```

### Create

`POST /todo_lists/:todo_list_id/items` with:

```json
{ "item": { "title": "Book the launch party venue", "description": "<p>Rooftop or the office?</p>", "due_date": "2026-09-15", "assigned_user_id": 2, "recurrence_rule": "weekly" } }
```

Only `title` is required. The item goes to the bottom of the list. Returns `201`
and the item, and notifies the assignee.

### Update

`PATCH /tools/:tool_id/todo/items/:id` with any of `title`, `description`,
`due_date` (or `null`), `assigned_user_id` (or `null`) and `recurrence_rule`
(`daily`, `weekly`, `monthly` or `null`) under `item`. Assigning someone new
notifies them.

### Complete

`POST /tools/:tool_id/todo/items/:item_id/completion` marks the item done, and
`DELETE` on the same path reopens it. Both return the item.

Completing an item that repeats adds a fresh open copy to the same list, with
the due date moved a day, week or month ahead. Comments and attachments stay
with the completed item. Completing an item that is already done changes
nothing, so retrying is safe. Completing someone else's item notifies them.

### Move

`PATCH /tools/:tool_id/todo/items/:item_id/position` with
`{"todo_list_id": 2, "position": 0}`. Both are optional: `todo_list_id`
defaults to the item's own list and `position` to the bottom. `position`
counts the list the way the page shows it, open items first and then completed
ones, with 0 at the top. Returns the item.

### Delete

`DELETE /tools/:tool_id/todo/items/:id` returns `204`.

## Comments

`POST /tools/:tool_id/todo/items/:item_id/comments` with `{"body": "<p>On it</p>"}`
returns `201` and the comment, and notifies the people on the tool.
`DELETE /tools/:tool_id/todo/items/:item_id/comments/:id` returns `204`. You can
delete your own comments, and owners can delete anyone's.

## Attachments

`POST /tools/:tool_id/todo/items/:item_id/attachments` as `multipart/form-data`
with a `file` field (25 MB max) returns `201` and the attachment. `download_url`
is a signed link that needs no token and works for a day. `DELETE .../attachments/:id` returns `204`.

## Lists

- `POST /tools/:tool_id/todo/lists` with `{"title": "Retro"}` adds a list at the end and returns `201`: `{"id": 4, "title": "Retro", "position": 2}`.
- `PATCH /tools/:tool_id/todo/lists/:id` with `{"title": "Launch retrospective"}` renames it.
- `DELETE /tools/:tool_id/todo/lists/:id` deletes it and its items, and returns `204`.

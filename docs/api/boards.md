# Boards

## Board

`GET /tools/:tool_id/board` returns the columns in order, each with its active
cards. Add `?archived=true` to get the archived cards instead.

```json
{
  "tool": { "id": 1, "name": "Product Launch", "type": "boards", "url": "...", "created_at": "...", "updated_at": "..." },
  "url": "https://dobase.example.com/tools/1/board",
  "columns": [
    {
      "id": 5,
      "name": "To Do",
      "position": 1,
      "cards": [
        {
          "id": 4,
          "title": "Write press release for launch day",
          "color": "yellow",
          "due_date": "2026-09-19",
          "position": 0,
          "column_id": 5,
          "archived": false,
          "assignee": { "id": 2, "name": "Marcus Rivera", "email_address": "marcus@moonshot-snacks.com" },
          "comments_count": 0,
          "attachments_count": 0,
          "url": "https://dobase.example.com/tools/1/board?card=4",
          "created_at": "...",
          "updated_at": "..."
        }
      ]
    }
  ]
}
```

## Cards

### Show

`GET /tools/:tool_id/board/cards/:id` returns the card fields above plus
`description`/`description_html`, `column`, `creator`, `comments` and
`attachments`:

```json
{
  "description": "Hero section with floating snacks",
  "description_html": "<p>Hero section with floating snacks</p>",
  "column": { "id": 6, "name": "In Progress", "position": 2 },
  "creator": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
  "comments": [
    {
      "id": 1,
      "body": "Love it",
      "body_html": "<p>Love it</p>",
      "user": { "id": 2, "name": "Marcus Rivera", "email_address": "marcus@moonshot-snacks.com" },
      "created_at": "..."
    }
  ],
  "attachments": [
    { "id": 3, "filename": "brief.pdf", "content_type": "application/pdf", "file_size": 20480, "download_url": "...", "created_at": "..." }
  ]
}
```

### Create

`POST /columns/:column_id/cards` with:

```json
{ "card": { "title": "Ship the API", "description": "<p>With a CLI</p>", "color": "green", "due_date": "2026-10-01", "assigned_user_id": 2 } }
```

Only `title` is required. The card goes to the bottom of the column. Returns
`201` and the card, and notifies the assignee.

### Update

`PATCH /tools/:tool_id/board/cards/:id` with any of `title`, `description`,
`color` (`red`, `orange`, `yellow`, `green`, `blue`, `purple` or `""`),
`due_date` (or `null`) and `assigned_user_id` (or `null`) under `card`.

### Move

`PATCH /tools/:tool_id/board/cards/:card_id/position` with
`{"column_id": 8, "position": 0}`. Both are optional: `column_id` defaults to
the card's own column and `position` (0 is the top) to the bottom. Returns the
card. Moving to another column notifies the assignee.

### Archive

`POST /tools/:tool_id/board/cards/:card_id/archive` archives the card, and
`DELETE` on the same path restores it. Both return the card.

### Delete

`DELETE /tools/:tool_id/board/cards/:id` returns `204`.

## Comments

`POST /tools/:tool_id/board/cards/:card_id/comments` with `{"body": "<p>On it</p>"}`
returns `201` and the comment. `DELETE /tools/:tool_id/board/cards/:card_id/comments/:id`
returns `204`. You can delete your own comments, and owners can delete anyone's.

## Attachments

`POST /tools/:tool_id/board/cards/:card_id/attachments` as `multipart/form-data`
with a `file` field (25 MB max) returns `201` and the attachment. `download_url`
is a signed link that needs no token and works for a day. `DELETE .../attachments/:id` returns `204`.

## Columns

- `POST /tools/:tool_id/board/columns` with `{"name": "Review"}` adds a column at the end and returns `201`.
- `PATCH /tools/:tool_id/board/columns/:id` with `{"name": "QA"}` renames it.
- `DELETE /tools/:tool_id/board/columns/:id` deletes it and its cards, and returns `204`.

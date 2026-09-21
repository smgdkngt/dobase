# Search

## Search every tool

`GET /search?q=launch` looks through every tool you share and returns what
matches, a handful of each kind:

```json
{
  "query": "launch",
  "results": [
    {
      "kind": "card",
      "title": "Write press release for launch day",
      "excerpt": null,
      "tool_id": 1,
      "tool_name": "Product Launch",
      "url": "https://dobase.example.com/tools/1/board?card=4"
    },
    {
      "kind": "document",
      "title": "Launch Day Runbook",
      "excerpt": "Launch Day Runbook Timeline (All times EST) 6:00 AM — Final check…",
      "tool_id": 4,
      "tool_name": "Launch Docs",
      "url": "https://dobase.example.com/tools/4/docs/documents/2"
    }
  ]
}
```

- `kind` is one of `card`, `todo`, `document`, `folder`, `file`, `message`,
  `event` and `mail`.
- Cards and todos match on their title, documents on their title and text,
  files and folders on their name, chat messages on their text, events on
  their title, and mail on its subject and sender.
- `excerpt` is the text around the match where there is more than a title:
  a document's words, a chat message, a mail's sender.
- `url` opens the result in the browser — a card or todo opens straight in
  its board or list.
- A query shorter than two characters returns no results. Archived cards and
  trashed mail are left out.

A read token is enough.

# Search

## Search every tool

`GET /search?q=launch` looks through every tool you share and returns what
matches, a handful of each kind, and how many there are of each:

```json
{
  "query": "launch",
  "kind": null,
  "totals": { "card": 7, "document": 1 },
  "results": [
    {
      "kind": "card",
      "title": "Write press release for launch day",
      "excerpt": null,
      "date": "2026-11-12T09:30:00Z",
      "archived": false,
      "tool_id": 1,
      "tool_name": "Product Launch",
      "url": "https://dobase.example.com/tools/1/board?card=4"
    },
    {
      "kind": "document",
      "title": "Launch Day Runbook",
      "excerpt": "Launch Day Runbook Timeline (All times EST) 6:00 AM — Final check…",
      "date": "2026-11-10T16:02:11Z",
      "archived": false,
      "tool_id": 4,
      "tool_name": "Launch Docs",
      "url": "https://dobase.example.com/tools/4/docs/documents/2"
    }
  ]
}
```

- What is typed is split into words, and a result has **every word**, in any
  order, each in any part of it. `"quoted words"` are looked for as they
  stand. Case doesn't matter.
- `kind` is one of `card`, `todo`, `document`, `folder`, `file`, `message`,
  `event` and `mail`.
- Cards match on their title, description, comments and their column's name;
  todos on their title, description, comments and their list's name;
  documents on their title and text; files and folders on their name; chat
  messages on their text; events on their title, place and description; and
  mail on its subject, the people on it, its text and its files' names (the
  mail search: every word as a word or the start of one).
- `excerpt` is the text around the match where the title doesn't hold every
  word: a description, a comment (with who wrote it), a document's words, a
  chat message, a mail's text. A mail found by its subject or sender has the
  sender.
- `date` is when it last changed: a chat message when it was sent, an event
  when it starts, mail when it was sent, an archived card when it was archived.
- `archived` is `true` for an archived card. Archived cards come after the
  open ones; trashed mail and junk are left out.
- `totals` counts the results of each kind that has any, up to 50. Five of each
  kind are in `results`; `GET /search?q=launch&kind=card` gives every one of
  that kind (up to 50) and says `"kind": "card"`.
- `url` opens the result in the browser — a card or todo opens straight in
  its board or list, an archived card too.
- A query shorter than two characters returns no results.

A read token is enough. The MCP tool `search` takes `query` and `kind`;
the CLI is `dobase search [--kind KIND] WORDS...`.

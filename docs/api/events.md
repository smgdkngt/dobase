# Events

What happens in your tools, one event each: mail that comes in, a card that
moves, a message in a chat. A program that wants to know reads them by number,
"everything after N", and so misses nothing and sees nothing twice. The CLI
does this for you: `dobase events --follow` prints one line of JSON per event
and keeps listening.

## Read events

`GET /events?after=811` returns the events after that number, oldest first:

```json
{
  "events": [
    {
      "id": 812,
      "kind": "card.moved",
      "at": "2026-10-09T14:03:11Z",
      "tool": { "id": 110, "name": "Projects", "type": "boards" },
      "ref": "110/44",
      "by": { "id": 1, "name": "Sem Goedknegt", "via": "Claude", "agent": true },
      "own": false,
      "data": { "title": "Event stream", "column": "Doing", "moved_from": "To do" }
    },
    {
      "id": 813,
      "kind": "mail.received",
      "at": "2026-10-09T14:05:40Z",
      "tool": { "id": 107, "name": "Mail", "type": "mail" },
      "ref": "107/5512",
      "by": null,
      "own": false,
      "data": { "from": "ann@example.com", "from_name": "Ann Lee", "subject": "Lunch on Friday?", "folder": "INBOX" }
    }
  ],
  "cursor": 813,
  "more": false,
  "gap": false
}
```

- `cursor` is the number to ask after next time. It moves on past events that
  are someone else's or that you filtered away, so keep it even when `events`
  is empty.
- `more` is true when there was more than a page (200 events): ask again with
  the new `cursor`.
- Without `after` and `since` you get no events, only the `cursor` the stream
  is at now: where a new listener starts.
- `since=2026-10-09T12:00:00Z` starts at a time instead of a number, for the
  first request of a listener that wants some history. Go on with `after`.
- `tool[]=107&tool[]=110` gives only those tools' events.
- `kind[]=mail&kind[]=card.moved` gives only those kinds: a family (`mail`,
  `card`, `chat`) or one kind. A kind that doesn't exist is a `422`.
- `skip_own=1` leaves out what was done with the token that asks.
- `gap` is true when events after your number are gone. They are kept for
  seven days; a listener that was away for longer has missed some and should
  look at its tools itself. The same is said for a number this server never
  gave. The events that are still there follow as usual.

You get the events of the tools you are on now, from the moment you came on.

In an event:

- `ref` is the thing it is about, as the CLI names it (`dobase card show 110/44`,
  `dobase mail show 107/5512`): a card, a mail message or a chat message. A
  deleted thing keeps its `ref`, which then finds nothing.
- `by` is who did it, `via` the name of the access token they did it with (null
  in the browser) and `agent` whether that token posts under its own name. It
  is null for what nobody here did: mail that arrived, what the mail sync found.
- `own` is true when it was done with the token that asks.
- `data` is a few words about it, never more: text of other people, cut to one
  line of 200 characters at most.

| Kind | When | `data` |
|------|------|--------|
| `mail.received` | Mail came in, found by the sync (every five minutes, or when asked) | `from`, `from_name`, `subject`, `folder` |
| `mail.moved` | Moved to another folder, or restored from the trash | the same, and `moved_from` |
| `mail.archived`, `mail.unarchived` | Archived or brought back | the same; `moved_from` when another mail program did it |
| `mail.deleted` | Moved to the trash, or gone from the server | the same; `moved_from` when it went to the trash |
| `card.created`, `card.archived`, `card.unarchived`, `card.deleted` | | `title`, `column` |
| `card.updated` | Title, description, due date, assignee or colour changed | `title`, `column`, `changed` (which of those), `assignee` when it changed |
| `card.moved` | Moved to another column (not within its own) | `title`, `column`, `moved_from` |
| `card.commented` | | `title`, `column`, `comment_id`, `excerpt` (140 characters) |
| `chat.message` | A message was posted | `excerpt` (140 characters), `files` (how many), `reply_to` |

A mail event says who the mail is from, what it is called and where it is. It
never carries the text of a mail. What is done to a conversation is an event
per message. Drafts give no events, and neither does reading or starring.

What another mail program does shows at the next sync: mail it moved, archived
or threw away is one event, and mail that is gone from the server altogether is
`mail.deleted`.

A read token is enough.

## Hearing that there is something

Asking every few seconds is not needed. The server says when there is a new
event, over the WebSocket the app's own pages use (Action Cable, at `/cable`):

1. Connect to `wss://dobase.example.com/cable` with the token in the
   `Authorization: Bearer` header and an `Origin` header that is the server's
   own address.
2. Subscribe: `{"command":"subscribe","identifier":"{\"channel\":\"EventsChannel\"}"}`.
3. Each new event in one of your tools arrives as `{"id":813}`, and nothing
   else. Ask `GET /events?after=…` for what happened.

Only a number goes over this line; what happened comes from the request, which
checks the token and the tools it may see each time. A connection made with a
token can open this channel and no other. Revoking the token closes it, with
`{"type":"disconnect","reason":"unauthorized","reconnect":false}`.

The server sends `{"type":"ping"}` every three seconds; a line that stays quiet
for longer is dead. Ask for events after every reconnect, and every few minutes
besides: a signal that got lost then only costs time.

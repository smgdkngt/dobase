# Dobase API

Dobase has a JSON API for scripts, integrations and AI assistants. It is the
same app you use in the browser: the same URLs, controllers and permissions,
answering in JSON. The [`dobase` command-line tool](../../cli/README.md) is
built on it.

- [Tools](tools.md): list, show, create and rename tools; who you are
- [Search](search.md): everything you share, searched at once
- [Boards](boards.md): columns, cards, comments and attachments
- [Todos](todos.md): lists, items, completions and comments
- [Docs](docs.md): documents
- [Chat](chat.md): messages
- [Notifications](notifications.md)
- [Mail](mail.md): conversations, flags, drafts and sending
- [Calendar](calendar.md): events
- [Files](files.md): folders, files, uploads and downloads

## Authentication

Create a personal access token under **Profile → API** in the browser. Give it a
name and pick a permission:

- **Read only**: `GET` and `HEAD` requests only.
- **Read and write**: everything the API offers.

The token is shown once. Dobase stores only a digest of it.

Send it as a bearer token and ask for JSON:

```bash
curl -H "Authorization: Bearer $DOBASE_TOKEN" -H "Accept: application/json" https://dobase.example.com/profile
```

A token acts as you inside your tools, with some limits. It cannot:

- change your account (profile, password, two-factor, sessions or other tokens)
- connect or change mail and calendar accounts
- invite or remove collaborators
- create or remove public share links
- trash or permanently delete mail
- delete whole tools

These actions answer `403` to token requests, so a leaked token can't lock you
out or leave anything behind that outlives revoking it.

A request that carries a token ignores any session cookie and doesn't need a
CSRF token. Reading a tool through the API doesn't mark anything as read and
doesn't clear your unread dots. Chat and mail have their own endpoints to mark
things read.

## Requests

- Send `Accept: application/json` on every request, file downloads included.
- Send bodies as JSON with `Content-Type: application/json`. File uploads use
  `multipart/form-data` instead.
- IDs are integers. Everything inside a tool lives under `/tools/:tool_id/...`.
- Dates are `YYYY-MM-DD`. Times are ISO 8601, in your profile's time zone.
- **Rich text** (card and todo descriptions, comments, chat messages, document
  content) is HTML. Responses carry each such field twice: `description` as
  plain text and `description_html` as the stored HTML. Send HTML back when you
  edit, so the formatting survives.
- Most objects have a `url` pointing at the page in the browser.

## Responses

| Status | Meaning |
|--------|---------|
| `200 OK` | The resource, after any change |
| `201 Created` | The new resource |
| `204 No Content` | Deleted |
| `401 Unauthorized` | Missing or invalid token: `{"error": "Invalid access token"}` |
| `403 Forbidden` | Read-only token, no access to the tool, or not allowed for tokens: `{"error": "..."}` |
| `404 Not Found` | No such record in this tool: `{"error": "Not found"}` |
| `409 Conflict` | Someone else is editing (documents): `{"error": "..."}` |
| `422 Unprocessable Content` | Validation failed: `{"errors": ["Title can't be blank"]}` |

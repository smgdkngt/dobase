# MCP

Dobase is an [MCP](https://modelcontextprotocol.io) server at `/mcp`, for Claude
and any other MCP client. A tool there does what the same command of the
`dobase` CLI does: it asks this API, with the client's token, and gives back the
API's JSON. So it sees what you see and may do what a token may do, nothing
more: no account, no mail or calendar logins, no sharing, no deleting a whole
tool.

## Connecting

- **Claude** (claude.ai, the desktop app, Claude Code): add a connector with
  the address `https://<your server>/mcp`. Claude registers itself, sends you
  to Dobase to sign in and say yes, and gets its own tokens. On that page you
  pick whether it may change things or only read, and whether what it writes
  shows under its own name ("Claude for Sem") or under yours ("Sem, via
  Claude").
- **Anything else**: send a personal access token from **Profile → API** as
  `Authorization: Bearer <token>`.

Both are one kind of token. A connection made by signing in shows under
**Profile → API** next to your personal tokens, and is ended there. One made
by Claude lasts thirty days from the moment you said yes, however often it is
refreshed; a login by code (`dobase login`) lasts until it goes thirty days
unused. Changing your password ends every connection; so does switching
"Connections from Claude and other programs" off on the same page. Every tool
call is listed there, refused ones too.

## OAuth

OAuth 2.1 for public clients, as the MCP specification asks:

- `GET /.well-known/oauth-protected-resource/mcp` (RFC 9728) and
  `GET /.well-known/oauth-authorization-server` (RFC 8414) describe the rest.
- `POST /oauth/register` (RFC 7591): dynamic client registration. Redirects may
  only go to `https://claude.ai`, `https://claude.com` (and their subdomains)
  or to this computer (`localhost`, `127.0.0.1`, `[::1]`). No client secrets.
- `GET /oauth/authorize`: the consent page. PKCE with `S256` only.
- `POST /oauth/token`: `authorization_code` (with `code_verifier`) and
  `refresh_token`. An access token lasts an hour. Every refresh gives a new
  pair and ends the old one; a refresh token or a code used a second time ends
  the whole connection.
- `POST /oauth/revoke` (RFC 7009) with `token` and `client_id`: either token of
  a pair ends the connection.

## Transport

Streamable HTTP, protocol version `2025-06-18` and later: `POST /mcp` with one
JSON-RPC message (batches are refused), answered with JSON. `initialize` starts
a session (`Mcp-Session-Id`), which belongs to the token that started it.
Sessions live in the server's memory, so after a deploy a client gets `404` and
starts a new one. `DELETE /mcp` ends a session. Requests are limited to 600 a
minute per person (tool calls and reads; starting a session or a ping doesn't count) and 8 MB each (files come along as base64).

## Live updates

A session can hear that something changed instead of asking again and again.
Open its stream with `GET /mcp` (`Accept: text/event-stream`, the session's
`Mcp-Session-Id`), then subscribe with `resources/subscribe`:

- `dobase://events`: there is a new event in your tools (what
  `dobase events --follow` listens for). Ask `event_list` after your cursor for
  what; `resources/read` of it gives the cursor to start from.
- `dobase://tools/<id>`: something in that tool changed, whoever changed it and
  from where (what an open page of the tool draws itself again for). Only for a
  tool you have; `resources/read` of it gives the tool.

Each change arrives on the stream as
`{"method": "notifications/resources/updated", "params": {"uri": "..."}}`,
saying only that it changed, never what. The stream is pinged every 30 seconds
and lasts 30 minutes at most; a session that sends nothing for 30 minutes ends.
A client keeps it going by sending `ping` now and then and opening the stream
again when it closes; after a `404` it starts a new session and subscribes
again. Revoking the token closes its streams at once. One token holds 20
sessions at most; past that its oldest ends.

## Tools

Named like the CLI's commands (`dobase card show` is `card_show`). Every result
is `structuredContent`, the API's JSON (a list comes as `{"items": [...]}`), and
the same JSON as text. A tool that only reads says `readOnlyHint`; one that
deletes or reaches outside Dobase says `destructiveHint` and does nothing until
it is called with `confirm: true`.

| Tool | What it does | API |
|------|--------------|-----|
| `whoami` | You, and the token in use | [Tools](tools.md#who-am-i) |
| `tool_list`, `tool_show`, `tool_create`, `tool_rename` | Your tools | [Tools](tools.md) |
| `search` | Every tool at once | [Search](search.md) |
| `notification_list`, `notification_read` | Your notifications | [Notifications](notifications.md) |
| `event_list` | What happened, by number | [Events](events.md) |
| `card_list`, `card_show`, `card_create`, `card_update`, `card_move`, `card_archive`, `card_unarchive`, `card_delete`\*, `card_comment`, `card_uncomment`\*, `card_attach`, `column_create`, `column_rename`, `column_delete`\* | Boards | [Boards](boards.md) |
| `todo_list`, `todo_show`, `todo_create`, `todo_update`, `todo_finish`, `todo_reopen`, `todo_move`, `todo_delete`\*, `todo_comment`, `todo_uncomment`\*, `todo_attach`, `todolist_create`, `todolist_rename`, `todolist_delete`\* | Todos | [Todos](todos.md) |
| `doc_list`, `doc_show`, `doc_create`, `doc_update`, `doc_delete`\* | Documents | [Docs](docs.md) |
| `chat_list`, `chat_post`, `chat_edit`, `chat_delete`\*, `chat_react`, `chat_read` | Chat | [Chat](chat.md) |
| `mail_list`, `mail_show`, `mail_contacts`, `mail_sync`, `mail_sync_status` | Conversations (`mail_show` leaves out the HTML unless `include_html`), people to mail, fetching new mail | [Mail](mail.md) |
| `mail_read`, `mail_unread`, `mail_star`, `mail_unstar`, `mail_archive`, `mail_unarchive`, `mail_move`, `mail_trash`, `mail_restore`, `mail_junk`, `mail_not_junk` | Flags and folders; trashing is a move, undone by `mail_restore` | [Mail](mail.md#flags-archive-and-folders) |
| `mail_draft`, `mail_update`, `mail_reply`, `mail_forward`, `mail_discard`, `mail_send`\* | Writing mail. Every one but `mail_send` saves a draft; `mail_send` sends a saved draft as it is | [Mail](mail.md#drafts) |
| `appointment_list`, `appointment_show`, `appointment_create`, `appointment_update`, `appointment_delete`\*, `calendar_sync` | Calendars | [Calendar](calendar.md) |
| `file_list`, `file_show`, `file_read`, `file_upload`, `file_rename`, `file_move`, `file_delete`\*, `folder_create`, `folder_rename`, `folder_move`, `folder_delete`\* | Files, and what can be read out of a file or attachment | [Files](files.md) |

\* destructive: does nothing without `confirm: true`.

Text (a description, a comment, a message, a mail, a document) is plain text,
written as paragraphs the way the CLI does, or HTML with `html: true`. Files go
along as `{"name", "content_base64"}`, a few megabytes in all. A person is
`me`, `none`, an id, an address or part of a name of someone the tool is shared
with; a column, list or calendar is its id or its name; a due date is
`YYYY-MM-DD`, `today`, `tomorrow` or `none`.

Mail is written as a draft first and sent only by `mail_send`, so what goes out
is always something that could be shown first. Downloading a file as it is
stays a plain HTTP request (`download_url`), with the same token.

Reading mail, a chat or notifications through MCP doesn't mark them read.

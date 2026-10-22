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
**Profile → API** next to your personal tokens, and is ended there. It lasts
thirty days from the moment you said yes, however often the client refreshes
it. Changing your password ends every connection; so does switching
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
starts a new one. `DELETE /mcp` ends a session. Requests are limited to 120 a
minute per person and 1 MB each.

## Tools

Named like the CLI's commands (`dobase card show` is `card_show`). Every result
is `structuredContent`, the API's JSON (a list comes as `{"items": [...]}`), and
the same JSON as text. A tool that only reads says `readOnlyHint`; one that
deletes or reaches outside Dobase says `destructiveHint` and does nothing until
it is called with `confirm: true`.

| Tool | What it does | API |
|------|--------------|-----|
| `whoami` | You, and the token in use | [Tools](tools.md#who-am-i) |
| `tool_list`, `tool_show` | Your tools, one tool | [Tools](tools.md) |
| `search` | Every tool at once | [Search](search.md) |
| `notification_list` | Your notifications | [Notifications](notifications.md) |
| `event_list` | What happened, by number | [Events](events.md) |
| `card_list`, `card_show` | A board, a card | [Boards](boards.md) |
| `todo_list`, `todo_show` | A todo tool, a todo | [Todos](todos.md) |
| `doc_list`, `doc_show` | Documents | [Docs](docs.md) |
| `chat_list` | A chat's messages | [Chat](chat.md) |
| `mail_list`, `mail_show`, `mail_contacts` | Conversations, one conversation (without its HTML unless `include_html`), people to mail | [Mail](mail.md) |
| `appointment_list`, `appointment_show` | A calendar's appointments, one appointment | [Calendar](calendar.md) |
| `file_list`, `file_show`, `file_read` | A folder, a file, what can be read out of a file or attachment | [Files](files.md) |

Reading mail, a chat or notifications through MCP doesn't mark them read.

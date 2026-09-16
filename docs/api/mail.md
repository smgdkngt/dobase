# Mail

A mail tool is connected to a real mailbox over IMAP and SMTP. Dobase keeps a
copy of the mail and syncs it with the mail server: flags, archiving and moves
are copied to the server in the background, and sending sends real email.

If the tool's mail account isn't connected yet, mail endpoints answer `404`
with `{"error": "Mail account not configured"}`. Connect it in the browser.

Tokens can't move mail to the trash (that deletes it on the mail server right
away), permanently delete mail, empty the trash, run bulk actions, or connect or
change the mail account. Those actions answer `403`. Archive instead.

## Conversations

### List

`GET /tools/:tool_id/mails` returns the conversations in a folder, newest first,
30 per page. Optional parameters:

- `folder`: `inbox` (default), `drafts`, `starred`, `sent`, `archive`, `trash`,
  or one of the `custom_folders`
- `q`: only messages whose subject, sender address or text contains this
- `page`: page number, from 1

```json
{
  "tool": { "id": 8, "name": "Mail", "type": "mail", "url": "...", "created_at": "...", "updated_at": "..." },
  "account": { "email_address": "sophie@moonshot-snacks.com", "display_name": null },
  "url": "https://dobase.example.com/tools/8/mails?folder=inbox",
  "folder": "inbox",
  "page": 1,
  "total_pages": 1,
  "total_count": 5,
  "counts": { "inbox_unread": 3, "drafts": 0, "trash": 0 },
  "folders": ["inbox", "drafts", "starred", "sent", "archive", "trash"],
  "custom_folders": ["Receipts"],
  "conversations": [
    {
      "id": 4,
      "thread_id": "<004@moonshot-snacks.com>",
      "subject": "Seed Round Follow-up",
      "from": "Rachel Kim",
      "from_address": "rachel@northstarvc.com",
      "preview": "Sophie, Thanks for the pitch yesterday. The team loved the product samples (the Nebula Bites were gone in 5 minutes)....",
      "sent_at": "2026-09-14T10:53:12.439Z",
      "read": false,
      "starred": true,
      "draft": false,
      "has_attachments": false,
      "unread_count": 1,
      "participants": ["Rachel Kim"],
      "messages_count": 1,
      "url": "https://dobase.example.com/tools/8/mails/4?folder=inbox"
    }
  ]
}
```

A conversation's `id` is its newest message in this folder, and its counts only
include messages in this folder. Use the `id` to show the conversation.

### Show

`GET /tools/:tool_id/mails/:id` returns the whole conversation the message
belongs to, oldest message first, whatever folder each message is in. Reading
a conversation this way doesn't mark it read.

```json
{
  "id": 4,
  "thread_id": "<004@moonshot-snacks.com>",
  "subject": "Seed Round Follow-up",
  "account": { "email_address": "sophie@moonshot-snacks.com", "display_name": null },
  "messages": [
    {
      "id": 4,
      "subject": "Seed Round Follow-up",
      "from_name": "Rachel Kim",
      "from_address": "rachel@northstarvc.com",
      "to": ["sophie@moonshot-snacks.com"],
      "cc": [],
      "sent_at": "2026-09-14T10:53:12.439Z",
      "read": false,
      "starred": true,
      "archived": false,
      "trashed": false,
      "draft": false,
      "folder": "INBOX",
      "message_id": "<004@moonshot-snacks.com>",
      "in_reply_to": null,
      "body": "Sophie, Thanks for the pitch yesterday. ...",
      "body_html": "<p>Sophie,</p><p>Thanks for the pitch yesterday. ...</p>",
      "attachments": [],
      "calendar_invites": [],
      "url": "https://dobase.example.com/tools/8/mails/4"
    },
    {
      "id": 7,
      "subject": "Re: Seed Round Follow-up",
      "from_name": "Sophie Chen",
      "from_address": "sophie@moonshot-snacks.com",
      "to": ["rachel@northstarvc.com"],
      "cc": [],
      "sent_at": "2026-09-14T11:53:12.459Z",
      "read": true,
      "starred": false,
      "archived": false,
      "trashed": false,
      "draft": false,
      "folder": "Sent",
      "message_id": "<007@moonshot-snacks.com>",
      "in_reply_to": "<004@moonshot-snacks.com>",
      "body": "Hi Rachel, So glad the team enjoyed the samples! ...",
      "body_html": "<p>Hi Rachel,</p><p>So glad the team enjoyed the samples! ...</p>",
      "attachments": [],
      "calendar_invites": [],
      "url": "https://dobase.example.com/tools/8/mails/7"
    }
  ]
}
```

- `body` is the plain-text part, or the text of the HTML for HTML-only mail.
  `body_html` is the HTML part as it arrived, or `null`. It isn't sanitized:
  sanitize it before you display it.
- `folder` is the folder on the mail server: `INBOX`, `Sent`, `Drafts` or a
  custom folder.
- Attachments look like
  `{"id": 3, "filename": "agenda.pdf", "content_type": "application/pdf", "file_size": 20480, "download_url": "..."}`.
  `download_url` is a signed link that needs no token and works for a day.
- Calendar invitations found in a message are listed under `calendar_invites`
  as `{"id", "summary", "starts_at", "ends_at", "all_day", "location", "organizer_name", "organizer_email", "status"}`.
- Drafts have `"draft": true`, and their `url` opens them in the compose form.

## Flags, archive and folders

Each of these returns `200` and the message (the fields above):

| Request | Does |
|---------|------|
| `POST /tools/:tool_id/mails/:id/read` | Mark read |
| `DELETE /tools/:tool_id/mails/:id/read` | Mark unread |
| `POST /tools/:tool_id/mails/:id/star` | Star (flag) |
| `DELETE /tools/:tool_id/mails/:id/star` | Unstar |
| `POST /tools/:tool_id/mails/:id/archive` | Archive |
| `DELETE /tools/:tool_id/mails/:id/archive` | Unarchive |
| `POST /tools/:tool_id/mails/:id/move` with `{"folder": "Receipts"}` | Move to a folder |

Read, star, archive and move changes are copied to the mail server in the
background. Archiving moves the message to the account's archive folder if it
has one, and otherwise only marks it read on the server.

The `folder` to move to is a folder name on the server: `INBOX`, `Sent` or one
of the `custom_folders`. An invalid name returns `422` with
`{"errors": ["Invalid folder name"]}`.

## Drafts

`POST /tools/:tool_id/mails/drafts` saves a draft. Nothing is sent:

```json
{ "to": "rachel@northstarvc.com", "subject": "Re: Seed Round Follow-up", "body": "<p>Thursday at 2pm works. See you then!</p>", "in_reply_to": "<004@moonshot-snacks.com>" }
```

`to` and `cc` are comma-separated addresses, and `body` is HTML. `in_reply_to`
is the `message_id` of the message you're replying to, and puts the draft in
its conversation. Returns `201` and the draft, which is copied to the server's
Drafts folder in the background.

`PATCH /tools/:tool_id/mails/drafts/:id` with any of the same fields changes
only those and returns the draft. Drafts are deleted in the browser.

## Sending

`POST /tools/:tool_id/mails` sends real email through the account's SMTP server:

```json
{ "to": "rachel@northstarvc.com", "cc": "", "bcc": "", "subject": "Re: Seed Round Follow-up", "body": "<p>Thursday at 2pm works. See you then!</p>" }
```

`to`, `cc` and `bcc` are comma-separated addresses, and `body` is HTML. An
address can have a name in front of it, as in `Rachel Kim <rachel@northstarvc.com>`.
It returns `201` with the recipients and subject, and a copy goes into Sent:

```json
{ "to": ["rachel@northstarvc.com"], "cc": [], "bcc": [], "subject": "Re: Seed Round Follow-up" }
```

To send a saved draft, send its fields with `"draft_id": 12`; the draft is
deleted once the email is sent. As in the browser, the email is made from the
fields in the request, not from what the draft holds.

An invalid address returns `422` without sending anything. A mail server that
refuses the email or can't be reached returns `422` too:

```json
{ "errors": ["Invalid email address: not an address"] }
```

Sent email has no `In-Reply-To` or `References` headers (replies from the
browser don't either), so mail programs can only match a reply to its
conversation by subject, and Dobase shows the sent copy as a conversation of
its own.

## Sync

`POST /tools/:tool_id/sync` starts fetching new mail from the server in the
background and returns the sync status, which `GET /tools/:tool_id/sync` also
returns:

```json
{ "status": "syncing", "last_synced_at": null }
```

`status` is `pending`, `syncing`, `synced` or `error`, and `last_synced_at` is
the time of the last successful sync.

## Contacts

`GET /tools/:tool_id/mails_contacts?q=ra` returns up to 10 people you have
mailed or received mail from whose name or address contains `q` (2 characters
or more):

```json
[
  { "email_address": "tom@galacticadventures.com", "name": "Tom Bradley" },
  { "email_address": "rachel@northstarvc.com", "name": "Rachel Kim" }
]
```

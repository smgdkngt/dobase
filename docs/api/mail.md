# Mail

A mail tool is connected to a real mailbox over IMAP and SMTP. Dobase keeps a
copy of the mail and syncs it with the mail server: flags, archiving and moves
are copied to the server in the background, and sending sends real email.

If the tool's mail account isn't connected yet, mail endpoints answer `404`
with `{"error": "Mail account not configured"}`. Connect it in the browser.

Tokens can't permanently delete mail, empty the trash, run bulk actions, or
connect or change the mail account. Those actions answer `403`. Tokens can move
mail to the trash when the mail server has a trash folder, see
[Trash](#trash).

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
      "sending": false,
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
      "sending": false,
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
- Mail sent from the compose page is in Sent with `"sending": true` until the
  mail server has taken it. Mail it refuses becomes a draft again.

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
background, and tried again for a few minutes while the server can't be
reached. Archiving moves the message to the account's archive folder if it
has one, and otherwise only marks it read on the server. Unarchiving moves it
from the archive folder back to the folder it was archived from, or marks it
unread when there's no archive folder. Mail that another mail program put in
the archive folder is listed under `archive` too; archiving it changes nothing,
and unarchiving moves it to the inbox.

Archive and move act on the whole conversation in the folder you're looking
at, the way the list shows it: pass that folder as `folder` when archiving and
as `current_folder` when moving (both default to `inbox`). Read and star only
change the message itself.

The `folder` to move to is `INBOX`, `Sent` (the server's sent folder, whatever
the server calls it) or one of the `custom_folders`, by the name the list gives
it. That is the name the mail server has for the folder, which for names with
`&` or letters outside ASCII is modified UTF-7: "Büro" is `B&APw-ro`, "R & D"
is `R &- D`. A folder the account doesn't have returns `422` with
`{"errors": ["Invalid folder name"]}`.

## Trash

| Request | Does |
|---------|------|
| `POST /tools/:tool_id/mails/:id/trash` | Move to the trash |
| `DELETE /tools/:tool_id/mails/:id/trash` | Restore from the trash |

Both return `200` and the message. Trashing moves the mail to the mail
server's trash folder, whatever the server calls it ("Deleted Messages",
"Bin", `[Gmail]/Trash`): here that folder is always `Trash`, and it isn't one
of the folders to move to. Nothing is deleted, and restoring moves the mail
back to the inbox.

Like archiving, trashing acts on the whole conversation in the folder you're
looking at: pass that folder as `folder` (default `inbox`). A draft is the
exception: it goes to the trash by itself, and the conversation it answers
stays where it is. A draft in the trash keeps `"draft": true` next to
`"trashed": true`, is left out of `drafts`, and its `url` opens it as mail.
Restoring makes it a draft again, in Drafts. The same goes for moving: a draft
moves by itself.

On a mail server without a trash folder, trashing deletes the mail there right
away. With a token that answers `422` and nothing happens:

```json
{ "error": "This account's mail server has no trash folder, so trashing would delete the mail there. Archive it instead." }
```

## Drafts

`POST /tools/:tool_id/mails/drafts` saves a draft. Nothing is sent:

```json
{ "to": "rachel@northstarvc.com", "subject": "Re: Seed Round Follow-up", "body": "<p>Thursday at 2pm works. See you then!</p>", "in_reply_to": "<004@moonshot-snacks.com>" }
```

`to`, `cc` and `bcc` are comma-separated addresses, and `body` is HTML. `in_reply_to`
is the `message_id` of the message you're replying to, and puts the draft in
its conversation. `quoted_message_id` is the `id` of the message a reply answers
or a forward forwards: it's kept out of `body` and added below it as it was
written (a reply's quote, or a forward's header block) when the mail goes out,
with the pictures it shows. `forward_attachment_ids` are the `id`s of
attachments of other mail in this account, which a forward takes along: they are
copied onto the draft. Returns `201` and the draft, which is copied to the
server's Drafts folder in the background, quote and attachments included.

`PATCH /tools/:tool_id/mails/drafts/:id` with any of the same fields changes
only those and returns the draft. Its attachments, `in_reply_to` and the
message it quotes stay as they are.

`POST /tools/:tool_id/mails/drafts/:id/attachments` attaches files to a draft:
a `multipart/form-data` request with one or more `files[]` parts. They are
added to the attachments the draft has, which can be 25 MB together. Returns
`201` and the draft, with every attachment listed. No files, or too much,
answers `422` with `errors`.

```bash
curl -X POST https://dobase.example.com/tools/8/mails/drafts/12/attachments \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  -F "files[]=@offer.pdf" -F "files[]=@terms.pdf"
```

A draft is discarded by moving it to the [trash](#trash). Drafts are deleted
for good in the browser.

## Sending

`POST /tools/:tool_id/mails` sends real email through the account's SMTP server:

```json
{ "to": "rachel@northstarvc.com", "cc": "", "bcc": "", "subject": "Re: Seed Round Follow-up", "body": "<p>Thursday at 2pm works. See you then!</p>", "in_reply_to": "<004@moonshot-snacks.com>" }
```

`to`, `cc` and `bcc` are comma-separated addresses, and `body` is HTML. An
address can have a name in front of it, as in `Rachel Kim <rachel@northstarvc.com>`.
A reply sends `in_reply_to`, the `message_id` of the message it answers: the
email gets `In-Reply-To` and `References` headers, so mail programs keep it in
that conversation, and its copy in Sent joins the conversation in Dobase. With
`quoted_message_id` the answered (or forwarded) message is quoted below `body`,
as for drafts.
The API sends right away and says whether it went (the compose page sends in the
background instead, and keeps mail that couldn't be sent as a draft).
It returns `201` with the recipients and subject, and a copy goes into Sent:

```json
{ "to": ["rachel@northstarvc.com"], "cc": [], "bcc": [], "subject": "Re: Seed Round Follow-up" }
```

To send a saved draft, send its fields with `"draft_id": 12`, and the `id`s of
its attachments as `forward_attachment_ids` (only the attachments named there
go out); the draft is deleted once the email is sent. As in the browser, the email is made from the
fields in the request, not from what the draft holds, so send a reply draft's
`in_reply_to` too.

An invalid address returns `422` without sending anything. A mail server that
refuses the email or can't be reached returns `422` too:

```json
{ "errors": ["Invalid email address: not an address"] }
```

## Sync

`POST /tools/:tool_id/sync` starts fetching new mail from the server in the
background and returns the sync status, which `GET /tools/:tool_id/sync` also
returns:

```json
{ "status": "syncing", "last_synced_at": null }
```

`status` is `pending`, `syncing`, `synced` or `error`, and `last_synced_at` is
the time of the last successful sync.

When the mail server turns down the username or password, the status is
`error` and the scheduled sync stops trying. It starts again when the account's
connection settings change, or after a `POST /tools/:tool_id/sync`.

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

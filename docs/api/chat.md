# Chat

## Messages

`GET /tools/:tool_id/chat` returns the latest 50 messages, oldest first:

```json
{
  "tool": { "id": 2, "name": "Team Chat", "type": "chat", "url": "...", "created_at": "...", "updated_at": "..." },
  "url": "https://dobase.example.com/tools/2/chat",
  "messages": [
    {
      "id": 19,
      "body": "Reply to a long one",
      "body_html": "<p>Reply to a long one</p>",
      "user": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
      "reply_to": {
        "id": 13,
        "user_name": "Jake Thompson",
        "preview": "I deployed the store to staging btw. Everything works except the checkout — turns out Stripe does..."
      },
      "files": [],
      "edited_at": null,
      "created_at": "..."
    },
    {
      "id": 20,
      "body": "With a file",
      "body_html": "<p>With a file</p>",
      "user": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
      "reply_to": null,
      "files": [
        { "filename": "notes.txt", "content_type": "text/plain", "byte_size": 18, "download_url": "..." }
      ],
      "edited_at": null,
      "created_at": "..."
    }
  ],
  "has_more": true
}
```

- `limit` sets how many messages you get, up to 200.
- `has_more` is true when there are older messages. To page back, pass the
  first message's id as `before`: `GET /tools/2/chat?before=19`.
- `reply_to` is the message this one answers, with a short plain-text preview,
  or `null`.
- `edited_at` is set once a message has been edited.
- `download_url` is a signed link that needs no token and works for a day.

Reading the chat doesn't mark it read. [Mark it read](#mark-as-read) when you
have dealt with the messages.

## Send a message

`POST /tools/:tool_id/chat/messages` with:

```json
{ "message": { "body": "<p>Standup moved to <strong>3pm</strong></p>", "reply_to_id": 15 } }
```

`reply_to_id` is optional and must be a message in the same chat. Returns `201`
and the message, and notifies the other people in the chat.

To attach files, send `multipart/form-data` instead, with `message[body]` and
a `message[files][]` field per file. The body may be empty when there are
files. A message takes up to 10 files of at most 50 MB each: images, PDFs,
office documents, plain text, CSV, Markdown, zip archives, audio and video.

## Edit a message

`PATCH /tools/:tool_id/chat/messages/:id` with `{"message": {"body": "<p>Standup moved to 4pm</p>"}}`
returns the message. Leaving `body` out leaves the text as it was, and a
request with no `message` at all answers `400`. You can only edit your own
messages; other messages answer `403`.

## Delete a message

`DELETE /tools/:tool_id/chat/messages/:id` returns `204`. You can delete your
own messages, and owners can delete anyone's.

## Mark as read

`POST /tools/:tool_id/chat/read` marks the chat read up to its latest message,
for you, and returns:

```json
{ "last_read_message_id": 19, "last_read_at": "2026-09-14T15:47:13.519Z" }
```

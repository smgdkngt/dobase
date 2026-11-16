# Notifications

## List notifications

`GET /notifications` returns your latest 20 notifications, newest first:

```json
[
  {
    "id": 77,
    "type": "ChatMessageNotifier",
    "message": "Marcus Rivera sent a message in Team Chat",
    "url": "https://dobase.example.com/tools/2/chat?message=19",
    "tool_id": 2,
    "read": false,
    "read_at": null,
    "created_at": "2026-09-14T15:50:53.187Z"
  },
  {
    "id": 75,
    "type": "DocumentCreatedNotifier",
    "message": "Marcus Rivera created Press kit",
    "url": "https://dobase.example.com/tools/4/docs/documents/8",
    "tool_id": 4,
    "read": true,
    "read_at": "2026-09-14T15:50:58.069Z",
    "created_at": "2026-09-14T15:50:52.954Z"
  }
]
```

- `limit` sets how many you get, up to 100. Dobase keeps your latest 100.
- `page` (from 1) goes further back, `limit` at a time: `GET /notifications?page=2`.
- `unread=true` leaves out the ones you have read.
- `url` is the page the notification is about, and `tool_id` the tool it
  happened in. A chat message, and a mention in one, lead to the message itself
  (`?message=`, see [Chat](chat.md#around-one-message)); a mention in a comment to
  its card or todo.

Nobody gets notifications they asked not to hear: someone whose profile says
"Mentions and assignments" gets only mentions, assignments and invitations, and
"Nothing" none at all. A mail that couldn't be sent, and a mail or calendar account
that stopped syncing, are said whatever the setting.

`type` is one of `CardAssignmentNotifier`, `CardCommentNotifier`,
`CardMovedNotifier`, `ChatMessageNotifier`, `MentionNotifier`,
`DocumentCreatedNotifier`, `FileUploadedNotifier`, `TodoAssignmentNotifier`,
`TodoCommentNotifier`, `TodoCompletedNotifier`, `CalendarEventCreatedNotifier`
and `ToolInvitationNotifier`.

## Mark as read

- `POST /notifications/:id/read` marks one notification read and returns it.
- `POST /notification_reads` marks all of them read and returns how many were
  unread: `{"marked_as_read": 3}`.

Clearing all notifications is only possible in the browser, on the
notifications page (`/notifications`).

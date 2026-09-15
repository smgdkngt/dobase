# Notifications

## List notifications

`GET /notifications` returns your latest 20 notifications, newest first:

```json
[
  {
    "id": 77,
    "type": "ChatMessageNotifier",
    "message": "Marcus Rivera sent a message in Team Chat",
    "url": "https://dobase.example.com/tools/2/chat",
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
- `unread=true` leaves out the ones you have read.
- `url` is the page the notification is about, and `tool_id` the tool it
  happened in.

`type` is one of `CardAssignmentNotifier`, `CardCommentNotifier`,
`CardMovedNotifier`, `ChatMessageNotifier`, `MentionNotifier`,
`DocumentCreatedNotifier`, `FileUploadedNotifier`, `TodoAssignmentNotifier`,
`TodoCommentNotifier`, `TodoCompletedNotifier`, `CalendarEventCreatedNotifier`
and `ToolInvitationNotifier`.

## Mark as read

- `POST /notifications/:id/read` marks one notification read and returns it.
- `POST /notification_reads` marks all of them read and returns how many were
  unread: `{"marked_as_read": 3}`.

Clearing all notifications is only possible in the browser.

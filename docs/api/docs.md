# Docs

## Documents

`GET /tools/:tool_id/docs` returns the documents, last edited first, each with
a plain-text `preview` of the start of its content.

```json
{
  "tool": { "id": 4, "name": "Launch Docs", "type": "docs", "url": "...", "created_at": "...", "updated_at": "..." },
  "url": "https://dobase.example.com/tools/4/docs",
  "documents": [
    {
      "id": 3,
      "title": "FAQ Draft",
      "preview": "Frequently Asked Questions Q: Can I actually eat these in space? A: Technically yes! Our snacks are crumb-free by design...",
      "locked": true,
      "locked_by": { "id": 2, "name": "Marcus Rivera", "email_address": "marcus@moonshot-snacks.com" },
      "updated_by": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
      "url": "https://dobase.example.com/tools/4/docs/documents/3",
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

`locked` is true while someone has the document open in the browser editor,
and `locked_by` says who (otherwise it is `null`). The lock is released when
they leave the editor, and lapses after five minutes if their browser stops
checking in.

## Show a document

`GET /tools/:tool_id/docs/documents/:id` returns the fields above plus
`creator` and the content, as plain text and as HTML:

```json
{
  "creator": { "id": 2, "name": "Marcus Rivera", "email_address": "marcus@moonshot-snacks.com" },
  "content": "Frequently Asked Questions\n\nQ: Can I actually eat these in space?\n\nA: Technically yes! ...",
  "content_html": "<h1>Frequently Asked Questions</h1>\n<p><strong>Q: Can I actually eat these in space?</strong></p>\n<p>A: Technically yes! ...</p>"
}
```

## Create a document

`POST /tools/:tool_id/docs/documents` with:

```json
{ "docs_document": { "title": "Launch plan", "content": "<h1>Launch plan</h1><p>Step one</p>" } }
```

Both are optional: without a title the document is called "Untitled". Returns
`201` and the document, and notifies the tool's other collaborators.

## Update a document

`PATCH /tools/:tool_id/docs/documents/:id` with `title` and/or `content` under
`docs_document`. The content replaces the whole document, so to change part of
it, fetch `content_html`, edit that and send all of it back. Returns the
document. Anyone reading it in the browser sees the change straight away.

While someone else has the document open in the editor, updates answer `409`,
because their editor would save over your change:

```json
{ "error": "Marcus Rivera is editing this document" }
```

Try again once `locked` is false. A lock of your own doesn't stop you.

## Delete a document

`DELETE /tools/:tool_id/docs/documents/:id` returns `204`.

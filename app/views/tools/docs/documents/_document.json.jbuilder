json.(document, :id, :title)
json.preview document.preview_text
json.locked document.locked?
json.partial! "users/optional_user", key: "locked_by", user: (document.locked_by if document.locked?)
json.partial! "users/optional_user", key: "updated_by", user: document.updated_by
json.url tool_docs_document_url(tool, document)
json.(document, :created_at, :updated_at)

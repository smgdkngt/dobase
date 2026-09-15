json.partial! "tools/docs/documents/document", document: @document, tool: @tool
json.partial! "users/optional_user", key: "creator", user: @document.created_by
json.partial! "shared/rich_text", name: "content", rich_text: @document.content

json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.url tool_docs_url(@tool)

json.documents @documents, partial: "tools/docs/documents/document", as: :document, tool: @tool

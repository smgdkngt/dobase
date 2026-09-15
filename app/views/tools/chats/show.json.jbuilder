json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.url tool_chat_url(@tool)

json.messages @messages, partial: "tools/chats/messages/message", as: :message
json.has_more @has_more

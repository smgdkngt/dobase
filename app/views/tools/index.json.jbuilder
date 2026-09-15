unread_tool_ids = Tool.unread_tool_ids_for(current_user)

json.array! @tools do |tool|
  json.partial! "tools/tool", tool: tool
  json.unread unread_tool_ids.include?(tool.id)
end

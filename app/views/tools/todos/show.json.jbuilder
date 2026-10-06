json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.url tool_todo_url(@tool)

json.lists @lists do |list|
  json.partial! "tools/todos/lists/list", list: list
  json.earlier_completed_count @earlier_completed.fetch(list.id, 0)
  json.items @items_by_list.fetch(list.id, []), partial: "tools/todos/items/item", as: :item, tool: @tool
end

json.partial! "tools/todos/items/item", item: @item, tool: @tool
json.partial! "shared/rich_text", name: "description", rich_text: @item.description

json.list do
  json.partial! "tools/todos/lists/list", list: @item.list
end
json.partial! "users/optional_user", key: "creator", user: @item.created_by

json.comments @item.comments.includes(:user, :rich_text_body).order(:created_at),
  partial: "tools/todos/items/comments/comment", as: :comment
json.attachments @item.attachments.includes(file_attachment: :blob),
  partial: "tools/todos/items/attachments/attachment", as: :attachment

json.partial! "tools/boards/cards/card", card: @card, tool: @tool
json.partial! "shared/rich_text", name: "description", rich_text: @card.description

json.column do
  json.partial! "tools/boards/columns/column", column: @card.column
end
json.partial! "users/optional_user", key: "creator", user: @card.created_by

json.comments @card.comments.includes(:user, :rich_text_body).order(:created_at),
  partial: "tools/boards/cards/comments/comment", as: :comment
json.attachments @card.attachments.includes(file_attachment: :blob),
  partial: "tools/boards/cards/attachments/attachment", as: :attachment

json.(card, :id, :title)
json.color card.color.presence
json.(card, :due_date, :position, :column_id)
json.archived card.archived?
json.partial! "users/optional_user", key: "assignee", user: card.assigned_user
json.comments_count card.comments.size
json.attachments_count card.attachments.size
json.url tool_board_url(tool, card: card.id)
json.(card, :created_at, :updated_at)

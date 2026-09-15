json.(item, :id, :title, :due_date, :position, :todo_list_id)
json.completed item.completed?
json.(item, :completed_at, :recurrence_rule)
json.partial! "users/optional_user", key: "assignee", user: item.assigned_user
json.comments_count item.comments.size
json.attachments_count item.attachments.size
json.url tool_todo_url(tool, item: item.id)
json.(item, :created_at, :updated_at)

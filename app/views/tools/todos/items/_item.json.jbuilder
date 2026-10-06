json.(item, :id, :title, :due_date, :position, :todo_list_id)
json.completed item.completed?
json.(item, :completed_at, :recurrence_rule)
json.has_description item.description.present?
json.partial! "users/optional_user", key: "assignee", user: item.assigned_user
# What draws the assignee's face: their picture, or their letters and colours
if (assignee = item.assigned_user)
  json.assignee_avatar do
    json.url assignee.avatar.attached? ? polymorphic_url(assignee.avatar.variant(resize_to_fill: [ 200, 200 ])) : nil
    json.initials "#{assignee.first_name[0]}#{assignee.last_name[0]}".upcase
    json.look assignee.avatar_look
  end
end
json.comments_count item.comments.size
json.attachments_count item.attachments.size
json.url tool_todo_url(tool, item: item.id)
json.(item, :created_at, :updated_at)

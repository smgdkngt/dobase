json.partial! "tools/tool", tool: @tool

collaborators = @tool.collaborators.includes(:user).order(:created_at)
json.role collaborators.find { |collaborator| collaborator.user_id == current_user.id }&.role

json.collaborators collaborators do |collaborator|
  json.partial! "users/user", user: collaborator.user
  json.role collaborator.role
end

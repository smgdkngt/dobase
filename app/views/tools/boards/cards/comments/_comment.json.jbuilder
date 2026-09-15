json.id comment.id
json.partial! "shared/rich_text", name: "body", rich_text: comment.body
json.user do
  json.partial! "users/user", user: comment.user
end
json.created_at comment.created_at

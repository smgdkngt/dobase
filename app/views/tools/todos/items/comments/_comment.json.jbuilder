json.id comment.id
json.partial! "shared/rich_text", name: "body", rich_text: comment.body
json.partial! "users/optional_user", key: "user", user: comment.user
json.created_at comment.created_at

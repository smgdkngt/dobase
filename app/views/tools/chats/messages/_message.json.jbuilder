json.id message.id
json.partial! "shared/rich_text", name: "body", rich_text: message.body
json.user do
  json.partial! "users/user", user: message.user
end

if (reply_to = message.reply_to)
  json.reply_to do
    json.id reply_to.id
    json.user_name reply_to.user.name
    json.preview reply_to.preview_text
  end
else
  json.reply_to nil
end

json.files message.files do |file|
  json.filename file.filename.to_s
  json.(file, :content_type, :byte_size)
  json.download_url rails_blob_url(file, disposition: "attachment")
end
json.reactions message.reaction_groups do |emoji, users|
  json.emoji emoji
  json.count users.size
  json.users users do |user|
    json.partial! "users/user", user: user
  end
end
json.(message, :edited_at, :created_at)

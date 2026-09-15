json.(message, :id, :subject, :from_name, :from_address)
json.to message.to_addresses_list
json.cc message.cc_addresses_list
json.(message, :sent_at, :read, :starred, :archived, :trashed, :draft, :folder, :message_id, :in_reply_to)
json.body message.plain_text_body
json.body_html message.body_html

json.attachments message.attachments do |attachment|
  json.(attachment, :id, :filename, :content_type, :file_size)
  json.download_url attachment.file.attached? ? rails_blob_url(attachment.file, disposition: "attachment") : nil
end

json.calendar_invites message.calendar_invites do |invite|
  json.(invite, :id, :summary, :starts_at, :ends_at, :all_day, :location, :organizer_name, :organizer_email, :status)
end

json.url message.draft? ? new_tool_mail_url(tool, draft_id: message.id) : tool_mail_url(tool, message)

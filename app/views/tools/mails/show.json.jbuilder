json.id @message.id
json.thread_id @message.thread_id
json.subject @message.normalized_subject.presence || "(No subject)"
json.account do
  json.(@mail_account, :email_address, :display_name)
end

json.messages @conversation_messages, partial: "tools/mails/message", as: :message, tool: @tool

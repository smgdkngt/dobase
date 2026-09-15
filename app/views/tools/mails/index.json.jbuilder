json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.account do
  json.(@mail_account, :email_address, :display_name)
end
json.url tool_mails_url(@tool, folder: @current_folder)

json.folder @current_folder
json.page @page
json.total_pages @total_pages
json.total_count @total_count
json.counts do
  json.inbox_unread @inbox_unread
  json.drafts @drafts_count
  json.trash @trash_count
end
json.folders %w[inbox drafts starred sent archive trash]
json.custom_folders @custom_folders

json.conversations @conversations do |conversation|
  json.extract! conversation, :id, :thread_id, :subject, :from, :from_address, :preview, :sent_at,
    :read, :starred, :draft, :has_attachments, :unread_count, :participants
  json.messages_count conversation[:count]
  json.url conversation[:draft] ? new_tool_mail_url(@tool, draft_id: conversation[:id]) : tool_mail_url(@tool, conversation[:id], folder: @current_folder)
end

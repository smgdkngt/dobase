json.(file, :id, :name, :content_type, :file_size, :folder_id)
json.partial! "users/optional_user", key: "creator", user: file.created_by
json.shared file.share.present?
json.url tool_files_item_url(tool, file)
json.download_url tool_files_item_download_url(tool, file)
json.(file, :created_at, :updated_at)

json.(folder, :id, :name, :parent_id)
json.shared folder.share.present?
json.url tool_files_url(tool, folder_id: folder.id)
json.(folder, :created_at, :updated_at)

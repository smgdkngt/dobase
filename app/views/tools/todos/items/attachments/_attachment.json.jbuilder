json.(attachment, :id, :filename, :content_type, :file_size)
json.download_url attachment.file.attached? ? rails_blob_url(attachment.file, disposition: "attachment") : nil
json.preview_url attachment.file.attached? ? file_preview_url(@tool, attachment.file, format: :json) : nil
json.created_at attachment.created_at

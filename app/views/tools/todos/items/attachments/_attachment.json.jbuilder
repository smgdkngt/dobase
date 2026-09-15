json.(attachment, :id, :filename, :content_type, :file_size)
json.download_url attachment.file.attached? ? rails_blob_url(attachment.file, disposition: "attachment") : nil
json.created_at attachment.created_at

kind = @preview.kind

json.id @attachment.id
json.name @preview.name
json.(@preview, :content_type, :byte_size)
json.kind kind
json.download_url rails_blob_url(@preview.blob, disposition: "attachment")

# What the app reads out of the file itself; a picture, a pdf, sound and video are downloaded
case kind
when "text"
  json.text @preview.preview_text
when "table"
  json.sheets @preview.sheets do |sheet|
    json.(sheet, :name, :rows, :more)
  end
when "document"
  json.blocks @preview.document_blocks do |block|
    json.kind block.kind
    json.text block.text if block.text
    json.level block.level if block.level
    json.rows block.rows if block.rows
  end
end

json.partial! "tools/files/items/item", file: @file, tool: @tool

if @file.share
  json.share do
    json.partial! "tools/files/shares/share", share: @file.share
  end
else
  json.share nil
end

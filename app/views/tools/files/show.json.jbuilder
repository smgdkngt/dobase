json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.url tool_files_url(@tool, folder_id: @folder&.id)

if @folder
  json.folder do
    json.(@folder, :id, :name, :parent_id)
  end
else
  json.folder nil
end

# From the top level down to the current folder's parent.
ancestors = @folder ? @folder.ancestors.reverse : []
json.breadcrumbs ancestors do |ancestor|
  json.(ancestor, :id, :name, :parent_id)
end

json.folders @folders.includes(:share), partial: "tools/files/folders/folder", as: :folder, tool: @tool
json.files @files.includes(:share, :created_by), partial: "tools/files/items/item", as: :file, tool: @tool

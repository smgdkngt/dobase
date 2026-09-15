json.(tool, :id, :name)
json.set! :type, tool.tool_type.slug
json.url tool_url(tool)
json.(tool, :created_at, :updated_at)

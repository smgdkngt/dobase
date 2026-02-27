# frozen_string_literal: true

puts "Seeding tool types..."

tool_types = [
  { name: "Todos", slug: "todos", icon: "check-square", description: "Task lists and to-do management" },
  { name: "Chat", slug: "chat", icon: "messages-square", description: "Real-time messaging and chat rooms" },
  { name: "Board", slug: "boards", icon: "layout", description: "Kanban boards for project management" },
  { name: "Files", slug: "files", icon: "folder", description: "File storage and sharing" },
  { name: "Docs", slug: "docs", icon: "file-text", description: "Collaborative documents and notes" },
  { name: "Mail", slug: "mail", icon: "mail", description: "Email client and inbox management" },
  { name: "Calendar", slug: "calendar", icon: "calendar", description: "Connect to your calendars" },
  { name: "Room", slug: "room", icon: "video", description: "Video conferencing rooms" }
]

tool_types.each do |attrs|
  ToolType.find_or_create_by!(slug: attrs[:slug]) do |tool_type|
    tool_type.name = attrs[:name]
    tool_type.icon = attrs[:icon]
    tool_type.description = attrs[:description]
    tool_type.enabled = true
  end
end

puts "Created #{ToolType.count} tool types"

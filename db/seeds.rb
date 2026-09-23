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

# =============================================================================
# Demo seed data — run with: SEED_DEMO=1 bin/rails db:seed
# =============================================================================
if ENV["SEED_DEMO"]
  require "open-uri"

  puts "\nSeeding demo data for Moonshot Snacks..."

  sophie = User.find_or_create_by!(email_address: "sophie@moonshot-snacks.com") do |u|
    u.first_name = "Sophie"
    u.last_name = "Chen"
    u.password = "password123"
  end
  marcus, priya, jake = Demo::Workspace.teammates(password: "password123")

  # Avatars come from the web here; the demo itself never fetches anything
  { sophie => "Sophie Chen", marcus => "Marcus Rivera", priya => "Priya Patel", jake => "Jake Thompson" }.each do |user, seed_name|
    next if user.avatar.attached?

    url = "https://api.dicebear.com/9.x/notionists/png?seed=#{CGI.escape(seed_name)}&size=200"
    begin
      avatar_data = URI.parse(url).open
      user.avatar.attach(io: avatar_data, filename: "#{seed_name.parameterize}.png", content_type: "image/png")
      puts "  Attached avatar for #{user.name}"
    rescue => e
      puts "  Skipped avatar for #{user.name}: #{e.message}"
    end
  end

  Demo::Workspace.new(sophie, teammates: [ marcus, priya, jake ]).build

  puts "  Created #{sophie.owned_tools.count} tools for #{sophie.name}: #{sophie.owned_tools.order(:id).pluck(:name).join(", ")}"
  puts "\nDemo data seeded successfully!"
  puts "  Log in as: sophie@moonshot-snacks.com / password123"
  puts "  Other users: marcus@, priya@, jake@ (same password)"
end

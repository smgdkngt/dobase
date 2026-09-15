# frozen_string_literal: true

module Dobase
  module Commands
    class Tools < Command
      TYPES = %w[boards todos docs chat files mail calendar room].freeze

      noun "tool", "The tools you have access to"

      command "tool list", "List your tools (* = new activity since you last looked)",
        flags: { type: [ "TYPE", "Only tools of this type: #{TYPES.join(", ")}" ] } do |type: nil|
        tools = get("/tools")
        tools = tools.select { |tool| tool["type"] == type } if type

        output(tools) do
          say "No tools." if tools.empty?
          table(tools.sort_by { |tool| [ tool["type"], tool["name"].downcase ] }.map { |tool|
            [ tool["id"], tool["type"], "#{tool["name"]}#{" *" if tool["unread"]}" ]
          }, indent: 0)
        end
      end

      command "tool show", "Show a tool, your role and its collaborators", args: %w[TOOL] do |ref|
        details = get("/tools/#{tool(ref)["id"]}")

        output(details) do
          say "#{details["name"]} (#{details["type"]} #{details["id"]})"
          field "Your role", details["role"]
          field "URL", details["url"]
          say
          say "Collaborators:"
          table(details["collaborators"].map { |user| [ user["id"], person(user), user["role"] ] })
        end
      end

      command "tool create", "Create a tool (mail and calendar still need their account connected in the browser)",
        args: %w[TYPE NAME] do |type, name|
        raise UsageError, "TYPE must be one of: #{TYPES.join(", ")}" unless TYPES.include?(type)

        created = post("/tools", tool: { name: name, tool_type: type })
        output(created) { say "Created #{created["type"]} tool #{quoted(created["name"])} (#{created["id"]}): #{created["url"]}" }
      end

      command "tool rename", "Rename a tool (owners only)", args: %w[TOOL NAME] do |ref, name|
        updated = patch("/tools/#{tool(ref)["id"]}", tool: { name: name })
        output(updated) { say "Renamed tool #{updated["id"]} to #{quoted(updated["name"])}." }
      end
    end
  end
end

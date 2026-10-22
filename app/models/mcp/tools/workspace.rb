# frozen_string_literal: true

module Mcp
  module Tools
    # Who you are, which tools you have, and what goes on across them
    module Workspace
      extend Declaring

      tool "whoami", "Who am I",
        "The signed-in person and the connection being used (its name, whether it may write, whether it writes as an agent).",
        read_only: true do
        get "/profile"
      end

      tool "tool_list", "List tools",
        "Every tool in the workspace (boards, todos, docs, chat, mail, calendar, files, room) with its id and type. " \
        "Start here: every other tool takes one of these ids.",
        read_only: true do
        get "/tools"
      end

      tool "tool_show", "Show a tool", "One tool: its name, type and the people it is shared with.",
        params: { tool_id: id("The tool's id", required: true) }, read_only: true do
        get "/tools/#{arg(:tool_id)}"
      end

      tool "search", "Search everything",
        "Search every tool for cards, todos, documents, chat messages, mail, files and appointments that match.",
        params: { query: text("What to look for", required: true) }, read_only: true do
        get "/search", q: arg(:query)
      end

      tool "notification_list", "List notifications", "Your latest notifications, newest first. Reading them doesn't mark them read.",
        params: { unread: flag("Only the unread ones"), limit: number("How many, up to 100", maximum: 100) },
        read_only: true do
        get "/notifications", unread: arg(:unread) ? "true" : nil, limit: arg(:limit)
      end

      tool "notification_read", "Mark notifications read", "Marks one notification read, or all of them without an id.",
        params: { notification_id: id("The notification's id") } do
        arg(:notification_id) ? post("/notifications/#{arg(:notification_id)}/read") : post("/notification_reads")
      end

      tool "tool_create", "Add a tool",
        "Adds a tool to the workspace. Boards start with three columns, todos with one list. Mail and calendar tools " \
        "need their account connected in the browser.",
        params: { name: text("Its name", required: true),
                  type: choice(%w[boards todos docs chat files mail calendar room], "Its kind", required: true) } do
        post "/tools", tool: { name: arg(:name), tool_type: arg(:type) }
      end

      tool "tool_rename", "Rename a tool", "Renames a tool. Owners only.",
        params: { tool_id: id("The tool's id", required: true), name: text("Its new name", required: true) } do
        patch "/tools/#{arg(:tool_id)}", tool: { name: arg(:name) }
      end

      tool "appearance_show", "Show the theme", "The theme you see Dobase in, its colours, and the built-in themes.",
        read_only: true do
        get "/appearance"
      end

      tool "appearance_update", "Pick a theme",
        "Picks a built-in theme (or a palette of your own with colors), a typeface, or one theme for a light and one " \
        "for a dark system. Only what is given changes; theme: null goes back to the app's own look.",
        params: {
          theme: { type: %w[string null], description: "A built-in theme's name, a name for colors of your own, or null" },
          colors: { type: "object", description: "A palette of your own, in the names of Omarchy's colors.toml" },
          scheme: choice(%w[light dark], "Which half of a light and dark pair this theme is"),
          typeface: { type: %w[string null], enum: [ "mono", nil ], description: "mono, or null for the app's own" },
          follow_system: flag("One theme for a light system and one for a dark one")
        } do
        patch "/appearance", %i[theme colors scheme typeface follow_system].select { given?(it) }.index_with { arg(it) }
      end

      tool "event_list", "List events",
        "What happened in your tools, oldest first, by number: mail received, sent or moved, cards made, moved or " \
        "commented on, chat messages, files added, appointments. Without after or since you get only the cursor, the " \
        "number to ask after next time. Gives a few words per event, never the text of a mail.",
        params: {
          after: number("Events after this number (a cursor from an earlier call)", minimum: 0),
          since: text("Events from this moment on (ISO 8601)"),
          tool_ids: list({ type: "integer" }, "Only these tools"),
          kinds: list({ type: "string" }, "Only these kinds, or families like mail or card"),
          skip_own: flag("Leave out what this connection did itself")
        }, read_only: true do
        get "/events", after: arg(:after), since: arg(:since), tool: arg(:tool_ids), kind: arg(:kinds),
          skip_own: arg(:skip_own) ? "1" : nil
      end
    end
  end
end

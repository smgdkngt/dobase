# frozen_string_literal: true

module Dobase
  module Commands
    class Todos < Command
      REPEATS = %w[daily weekly monthly].freeze
      ITEM_FLAGS = {
        description: [ "TEXT", "Description (plain text, or HTML with --html)" ],
        html: [ nil, "The description is HTML" ],
        due: [ "DATE", "Due date: YYYY-MM-DD, today, tomorrow or none" ],
        assignee: [ "USER", "me, none, a user id, email or name" ],
        repeat: [ "RULE", "#{REPEATS.join(", ")} or none" ]
      }.freeze

      noun "todo", "Todos on lists (todos tools)"
      noun "todolist", "Lists in a todos tool"

      command "todo list", "Show a todos tool: its lists with their open and recently completed todos", args: %w[TOOL],
        flags: { completed: [ nil, "Show every completed todo instead" ] } do |ref, completed: false|
        todos_tool = tool(ref, "todos")
        todo = get("/tools/#{todos_tool["id"]}/todo", completed: completed || nil)

        output(todo) do
          say "#{todos_tool["name"]} (todos #{todos_tool["id"]}) #{todo["url"]}"
          todo["lists"].each do |list|
            say
            say "#{list["title"]} [list #{list["id"]}]"
            say "  (no #{"completed " if completed}todos)" if list["items"].empty?
            table(list["items"].map { |item|
              [ "#{todos_tool["id"]}/#{item["id"]}", item["completed"] ? "[x]" : "[ ]", item["title"], item_summary(item) ]
            })
          end
        end
      end

      command "todo show", "Show a todo with its description, comments and attachments", args: %w[TOOL/ITEM] do |ref|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        item = get("/tools/#{todos_tool["id"]}/todo/items/#{id}")

        output(item) do
          say "#{item["title"]} (todo #{todos_tool["id"]}/#{item["id"]})"
          field "List", "#{todos_tool["name"]} › #{item.dig("list", "title")}"
          field "Status", item["completed"] ? "done #{moment(item["completed_at"])}" : "open"
          field "Assignee", person(item["assignee"])
          field "Due", item["due_date"]
          field "Repeats", item["recurrence_rule"]
          field "Created", [ moment(item["created_at"]), item.dig("creator", "name") ].compact.join(" by ")
          field "URL", item["url"]

          unless item["description"].strip.empty?
            say
            say "Description:"
            paragraph item["description"]
          end

          say
          say "Comments (#{item["comments"].size}):"
          item["comments"].each do |comment|
            say "  #{comment.dig("user", "name")} · #{moment(comment["created_at"])} [comment #{comment["id"]}]"
            paragraph comment["body"], indent: 4
          end

          unless item["attachments"].empty?
            say
            say "Attachments (#{item["attachments"].size}):"
            table(item["attachments"].map { |attachment| [ attachment["filename"], bytes(attachment["file_size"]), attachment["download_url"] ] })
          end
        end
      end

      command "todo create", "Add a todo to the bottom of a list (the first list unless --list)", args: %w[TOOL TITLE],
        flags: ITEM_FLAGS.merge(list: [ "LIST", "List id or name" ]) do |ref, title, list: nil, **options|
        todos_tool = tool(ref, "todos")
        target = find_list(todos_tool, list)

        item = post("/todo_lists/#{target["id"]}/items", item: item_attributes(todos_tool, options).merge(title: title))
        output(item) { say "Created todo #{todos_tool["id"]}/#{item["id"]} #{quoted(item["title"])} in #{target["title"]}: #{item["url"]}" }
      end

      command "todo update", "Change a todo's title, description, due date, assignee or repeat", args: %w[TOOL/ITEM],
        flags: ITEM_FLAGS.merge(title: [ "TEXT", "New title" ]) do |ref, title: nil, **options|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        attributes = item_attributes(todos_tool, options)
        attributes[:title] = title if title
        raise UsageError, "Nothing to update. See `dobase help todo`." if attributes.empty?

        item = patch("/tools/#{todos_tool["id"]}/todo/items/#{id}", item: attributes)
        output(item) { say "Updated todo #{todos_tool["id"]}/#{item["id"]} #{quoted(item["title"])}." }
      end

      command "todo finish", "Mark a todo as done (a repeating todo comes back with its next due date)", args: %w[TOOL/ITEM] do |ref|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        item = post("/tools/#{todos_tool["id"]}/todo/items/#{id}/completion")

        output(item) do
          say "Completed todo #{todos_tool["id"]}/#{item["id"]} #{quoted(item["title"])}."
          say "It repeats #{item["recurrence_rule"]}, so the next one is on the list." if item["recurrence_rule"]
        end
      end

      command "todo reopen", "Mark a completed todo as not done", args: %w[TOOL/ITEM] do |ref|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        item = delete("/tools/#{todos_tool["id"]}/todo/items/#{id}/completion")
        output(item) { say "Reopened todo #{todos_tool["id"]}/#{item["id"]} #{quoted(item["title"])}." }
      end

      command "todo move", "Move a todo to another list, or to a position within its list", args: %w[TOOL/ITEM [LIST]],
        flags: { position: [ "N", "Position in the list, 1 = top (default: bottom)" ] } do |ref, list = nil, position: nil|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        raise UsageError, "Give a LIST, a --position, or both." if list.nil? && position.nil?

        target = find_list(todos_tool, list) if list
        body = { todo_list_id: target&.dig("id"), position: position && [ position.to_i - 1, 0 ].max }.compact
        item = patch("/tools/#{todos_tool["id"]}/todo/items/#{id}/position", body)
        output(item) { say "Moved todo #{todos_tool["id"]}/#{item["id"]} #{quoted(item["title"])} to #{item.dig("list", "title")}, position #{item["position"] + 1}." }
      end

      command "todo delete", "Delete a todo permanently, with its comments and attachments", args: %w[TOOL/ITEM] do |ref|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        delete("/tools/#{todos_tool["id"]}/todo/items/#{id}")
        output(nil) { say "Deleted todo #{todos_tool["id"]}/#{id}." }
      end

      command "todo comment", "Comment on a todo", args: %w[TOOL/ITEM TEXT],
        flags: { html: [ nil, "TEXT is HTML" ] } do |ref, body, html: false|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        comment = post("/tools/#{todos_tool["id"]}/todo/items/#{id}/comments", body: rich_text(body, html: html))
        output(comment) { say "Commented on todo #{todos_tool["id"]}/#{id} [comment #{comment["id"]}]." }
      end

      command "todo attach", "Attach files to a todo (25 MB max each)", args: %w[TOOL/ITEM PATH...] do |ref, *paths|
        todos_tool, id = tool_and_id(ref, "todos", "item")
        missing = paths.reject { |path| File.file?(path) }
        raise UsageError, "No such file: #{missing.join(", ")}" if missing.any?

        attachments = paths.map { |path| client.upload("/tools/#{todos_tool["id"]}/todo/items/#{id}/attachments", files: { file: path }) }
        output(attachments) { attachments.each { |attachment| say "Attached #{attachment["filename"]} (#{bytes(attachment["file_size"])}) to todo #{todos_tool["id"]}/#{id}." } }
      end

      command "todolist create", "Add a list to the end of a todos tool", args: %w[TOOL TITLE] do |ref, title|
        todos_tool = tool(ref, "todos")
        list = post("/tools/#{todos_tool["id"]}/todo/lists", title: title)
        output(list) { say "Created list #{todos_tool["id"]}/#{list["id"]} #{quoted(list["title"])}." }
      end

      command "todolist rename", "Rename a list", args: %w[TOOL/LIST TITLE] do |ref, title|
        todos_tool, id = tool_and_id(ref, "todos", "list")
        list = patch("/tools/#{todos_tool["id"]}/todo/lists/#{id}", title: title)
        output(list) { say "Renamed list #{todos_tool["id"]}/#{list["id"]} to #{quoted(list["title"])}." }
      end

      command "todolist delete", "Delete a list and every todo on it", args: %w[TOOL/LIST] do |ref|
        todos_tool, id = tool_and_id(ref, "todos", "list")
        delete("/tools/#{todos_tool["id"]}/todo/lists/#{id}")
        output(nil) { say "Deleted list #{todos_tool["id"]}/#{id}." }
      end

      private

      def item_summary(item)
        [
          ("done #{day(item["completed_at"])}" if item["completed"]),
          ("due #{item["due_date"]}" if item["due_date"]),
          ("@#{item.dig("assignee", "name")}" if item["assignee"]),
          ("repeats #{item["recurrence_rule"]}" if item["recurrence_rule"]),
          (count(item["comments_count"], "comment") if item["comments_count"].positive?),
          (count(item["attachments_count"], "file") if item["attachments_count"].positive?)
        ].compact.join("  ")
      end

      def find_list(todos_tool, ref)
        lists = get("/tools/#{todos_tool["id"]}/todo")["lists"]
        return lists.first || raise(Error, "#{todos_tool["name"]} has no lists.") if ref.nil?

        match = lists.find { |list| list["id"].to_s == ref } ||
          lists.find { |list| list["title"].casecmp?(ref) } ||
          lists.find { |list| list["title"].downcase.start_with?(ref.downcase) }
        match || raise(Error, "No list matches #{quoted(ref)}. Lists: #{lists.map { |list| list["title"] }.join(", ")}")
      end

      def item_attributes(todos_tool, options)
        attributes = {}
        attributes[:description] = rich_text(options[:description], html: options[:html]) if options[:description]
        attributes[:due_date] = date_param(options[:due]) if options[:due]
        attributes[:assigned_user_id] = user_id(todos_tool, options[:assignee]) if options[:assignee]
        if options[:repeat]
          raise UsageError, "--repeat must be one of: #{REPEATS.join(", ")}, none" unless (REPEATS + [ "none" ]).include?(options[:repeat])
          attributes[:recurrence_rule] = options[:repeat] == "none" ? nil : options[:repeat]
        end
        attributes
      end
    end
  end
end

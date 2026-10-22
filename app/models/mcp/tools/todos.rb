# frozen_string_literal: true

module Mcp
  module Tools
    module Todos
      extend Declaring

      REPEATS = %w[daily weekly monthly none].freeze

      def self.todo_params
        {
          description: text("Notes, plain text (or HTML with html: true)"),
          html: html_flag,
          due: due,
          assignee: assignee,
          repeat: choice(REPEATS, "How it comes back once done, or none")
        }
      end

      def self.todo_attributes(call)
        call.instance_exec do
          attributes = {}
          attributes[:description] = rich(:description) if given?(:description)
          attributes[:due_date] = day(:due) if given?(:due)
          attributes[:assigned_user_id] = person(arg(:tool_id), arg(:assignee)) if given?(:assignee)
          attributes[:recurrence_rule] = arg(:repeat) == "none" ? nil : arg(:repeat) if given?(:repeat)
          attributes
        end
      end

      def self.item_path(call, suffix = nil)
        "/tools/#{call.arg(:tool_id)}/todo/items/#{call.arg(:todo_id)}#{suffix}"
      end

      def self.item
        { tool_id: tool_id("todos"), todo_id: id("The todo's id", required: true) }
      end

      def self.lists(call)
        call.get("/tools/#{call.arg(:tool_id)}/todo")["lists"]
      end

      tool "todo_list", "Show a todo tool",
        "A todo tool's lists in order, each with its open items and those completed in the last day.",
        params: { tool_id: tool_id("todos"), completed: flag("Every completed item instead") }, read_only: true do
        get "/tools/#{arg(:tool_id)}/todo", completed: arg(:completed) ? "true" : nil
      end

      tool "todo_show", "Show a todo", "A todo with its notes, assignee, due date, comments and attachments.",
        params: item, read_only: true do
        get Todos.item_path(self)
      end

      tool "todo_create", "Add a todo", "Adds a todo to the bottom of a list (the first list unless list is given).",
        params: { tool_id: tool_id("todos"), title: text("The todo", required: true), list: text("The list's id or title") }
          .merge(todo_params) do
        lists = Todos.lists(self)
        raise Tool::Error, "This todo tool has no lists" if lists.empty?

        list = arg(:list) ? named(lists, arg(:list), "title", "list") : lists.first
        post "/todo_lists/#{list["id"]}/items", item: Todos.todo_attributes(self).merge(title: arg(:title))
      end

      tool "todo_update", "Change a todo", "Changes a todo's title, notes, due date, assignee or how it repeats.",
        params: item.merge(title: text("A new title")).merge(todo_params) do
        attributes = Todos.todo_attributes(self)
        attributes[:title] = arg(:title) if given?(:title)
        raise Tool::Error, "Nothing to change" if attributes.empty?

        patch Todos.item_path(self), item: attributes
      end

      tool "todo_finish", "Finish a todo", "Marks a todo done. A repeating todo comes back with its next due date.",
        params: item do
        post Todos.item_path(self, "/completion")
      end

      tool "todo_reopen", "Reopen a todo", "Marks a finished todo as not done.", params: item do
        delete Todos.item_path(self, "/completion")
      end

      tool "todo_move", "Move a todo", "Moves a todo to another list, or to a position within its list.",
        params: item.merge(list: text("The list's id or title"), position: number("Its place in the list, 1 = top")) do
        raise Tool::Error, "Give a list, a position, or both" unless arg(:list) || arg(:position)

        body = {}
        body[:todo_list_id] = named(Todos.lists(self), arg(:list), "title", "list")["id"] if arg(:list)
        body[:position] = arg(:position) - 1 if arg(:position)
        patch Todos.item_path(self, "/position"), body
      end

      tool "todo_delete", "Delete a todo", "Deletes a todo for good, with its comments and attachments.",
        params: item, destructive: true do
        delete Todos.item_path(self)
      end

      tool "todo_comment", "Comment on a todo", "Adds a comment to a todo.",
        params: item.merge(text: text("The comment, plain text (or HTML with html: true)", required: true), html: html_flag) do
        post Todos.item_path(self, "/comments"), body: rich(:text)
      end

      tool "todo_uncomment", "Delete a comment from a todo", "Deletes a comment: your own, or anyone's on a tool you own.",
        params: item.merge(comment_id: id("The comment's id", required: true)), destructive: true do
        delete Todos.item_path(self, "/comments/#{arg(:comment_id)}")
      end

      tool "todo_attach", "Attach files to a todo", "Attaches files to a todo, 25 MB each at most.",
        params: item.merge(files: file_list("The files", required: true)) do
        files(:files).map { upload Todos.item_path(self, "/attachments"), file: it }
      end

      tool "todolist_create", "Add a list", "Adds a list to the end of a todo tool.",
        params: { tool_id: tool_id("todos"), title: text("Its title", required: true) } do
        post "/tools/#{arg(:tool_id)}/todo/lists", title: arg(:title)
      end

      tool "todolist_rename", "Rename a list", "Renames a todo list.",
        params: { tool_id: tool_id("todos"), list_id: id("The list's id", required: true), title: text("Its new title", required: true) } do
        patch "/tools/#{arg(:tool_id)}/todo/lists/#{arg(:list_id)}", title: arg(:title)
      end

      tool "todolist_delete", "Delete a list", "Deletes a todo list and every todo in it, for good.",
        params: { tool_id: tool_id("todos"), list_id: id("The list's id", required: true) }, destructive: true do
        delete "/tools/#{arg(:tool_id)}/todo/lists/#{arg(:list_id)}"
      end
    end
  end
end

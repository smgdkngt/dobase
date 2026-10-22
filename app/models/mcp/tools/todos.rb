# frozen_string_literal: true

module Mcp
  module Tools
    module Todos
      extend Declaring

      tool "todo_list", "Show a todo tool",
        "A todo tool's lists in order, each with its open items and those completed in the last day.",
        params: { tool_id: tool_id("todos"), completed: flag("Every completed item instead") }, read_only: true do
        get "/tools/#{arg(:tool_id)}/todo", completed: arg(:completed) ? "true" : nil
      end

      tool "todo_show", "Show a todo", "A todo with its notes, assignee, due date, comments and attachments.",
        params: { tool_id: tool_id("todos"), todo_id: id("The todo's id", required: true) }, read_only: true do
        get "/tools/#{arg(:tool_id)}/todo/items/#{arg(:todo_id)}"
      end
    end
  end
end

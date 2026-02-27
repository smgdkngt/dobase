# frozen_string_literal: true

require "test_helper"

module Todos
  class ListTest < ActiveSupport::TestCase
    test "belongs to tool" do
      list = todo_lists(:main)
      assert_equal tools(:my_todos), list.tool
    end

    test "has many items" do
      list = todo_lists(:main)
      assert list.items.count >= 2
    end

    test "dependent destroy removes items" do
      list = todo_lists(:main)
      item_count = list.items.count

      assert_difference "Todos::Item.count", -item_count do
        list.destroy!
      end
    end

    test "validates title presence" do
      list = Todos::List.new(tool: tools(:my_todos))
      assert_not list.valid?
      assert list.errors[:title].any?
    end

    test "create_default_for creates a list" do
      tool = tools(:my_todos)

      assert_difference "Todos::List.count", 1 do
        Todos::List.create_default_for(tool)
      end

      assert_equal "To Do", tool.todo_lists.last.title
    end

    test "new todos tool automatically creates default list" do
      new_tool = Tool.create!(name: "New Todos", tool_type: tool_types(:todos), owner: users(:one))

      assert_equal 1, new_tool.todo_lists.count
      assert_equal "To Do", new_tool.todo_lists.first.title
    end
  end
end

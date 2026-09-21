# frozen_string_literal: true

require "application_system_test_case"

class TodosTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_todos)
    sign_in_as users(:one)
  end

  test "a todo moves to another list from its own dialog, without dragging" do
    item = todo_items(:pending_one)
    visit tool_todo_path(@tool, item: item.id)
    assert_selector "dialog[open] h2", text: item.title

    within("dialog[open]") { select "Backlog", from: "List" }

    # The dialog shows the todo again, and it is in Backlog now
    within("dialog[open]") do
      assert_selector "h2", text: item.title
      assert_select "List", selected: "Backlog"
    end
    assert_equal todo_lists(:backlog), item.reload.list
  end
end

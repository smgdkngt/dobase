# frozen_string_literal: true

require "application_system_test_case"

# The board and todo pages go back to themselves when their dialog closes. A
# dialog also closes when the page goes somewhere else — the command palette, a
# notification link — and that visit has to win.
class DialogNavigationTest < ApplicationSystemTestCase
  setup { sign_in_as users(:one) }

  test "going to another tool with a card open goes there, not back to the board" do
    visit tool_board_path(tools(:project_board), card: cards(:first_task).id)
    assert_selector "dialog[open] h2", text: "First task"

    turbo_visit tool_todo_path(tools(:my_todos))

    assert_current_path tool_todo_path(tools(:my_todos))
    assert_no_current_path tool_board_path(tools(:project_board)), ignore_query: true, wait: 2
  end

  test "going to another tool with a todo open goes there, not back to the list" do
    visit tool_todo_path(tools(:my_todos), item: todo_items(:pending_one).id)
    assert_selector "dialog[open] h2", text: todo_items(:pending_one).title

    turbo_visit tool_board_path(tools(:project_board))

    assert_current_path tool_board_path(tools(:project_board))
    assert_no_current_path tool_todo_path(tools(:my_todos)), ignore_query: true, wait: 2
  end

  test "closing a card still takes you back to the board without it" do
    visit tool_board_path(tools(:project_board), card: cards(:first_task).id)
    assert_selector "dialog[open] h2", text: "First task"

    within("dialog[open]") { click_on "Close" }

    assert_no_selector "dialog[open]"
    assert_current_path tool_board_path(tools(:project_board))
  end

  private

  def turbo_visit(path)
    page.execute_script("Turbo.visit(arguments[0])", path)
  end
end

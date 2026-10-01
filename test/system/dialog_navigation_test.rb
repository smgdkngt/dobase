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

  test "a card opened right after closing another stays open when the board catches up" do
    visit tool_board_path(tools(:project_board), card: cards(:first_task).id)
    assert_selector "dialog[open] h2", text: "First task"

    on_a_slow_connection do
      within("dialog[open]") { click_on "Close" }
      assert_no_selector "dialog[open]"
      find("[data-card-id='#{cards(:second_task).id}']").click
      assert_selector "dialog[open] h2", text: "Second task"

      # Well past the refresh that closing the first card asked for
      sleep 2
      assert_selector "dialog[open] h2", text: "Second task"
      assert_current_path tool_board_path(tools(:project_board))
    end

    # The refresh that was let go comes with the next close
    cards(:third_task).update!(title: "Renamed meanwhile")
    within("dialog[open]") { click_on "Close" }
    assert_text "Renamed meanwhile"
    assert_no_selector "dialog[open]"
  end

  test "a todo opened right after closing another stays open when the list catches up" do
    visit tool_todo_path(tools(:my_todos), item: todo_items(:pending_one).id)
    assert_selector "dialog[open] h2", text: todo_items(:pending_one).title

    on_a_slow_connection do
      within("dialog[open]") { click_on "Close" }
      assert_no_selector "dialog[open]"
      find("[data-action~='click->todo#openItem'][data-item-id='#{todo_items(:pending_two).id}']").click
      assert_selector "dialog[open] h2", text: todo_items(:pending_two).title

      sleep 2
      assert_selector "dialog[open] h2", text: todo_items(:pending_two).title
      assert_current_path tool_todo_path(tools(:my_todos))
    end
  end

  test "a card typed right after closing another keeps its text when the board catches up" do
    visit tool_board_path(tools(:project_board))
    wait_for_turbo
    wait_for_stimulus "board"
    find("[data-card-id='#{cards(:first_task).id}']").click
    assert_selector "dialog[open] h2", text: "First task"

    on_a_slow_connection do
      within("dialog[open]") { click_on "Close" }
      assert_no_selector "dialog[open]"
      first("[data-board-target='addCardBtn']").click
      first("[data-board-target='addCardInput']").send_keys("Buy stamps")

      sleep 2
      assert_equal "Buy stamps", first("[data-board-target='addCardInput']").value
    end
  end

  private

  # Every request takes most of a second, as on a train
  def on_a_slow_connection
    page.driver.browser.network_conditions = { offline: false, latency: 700, throughput: 1_000_000 }
    yield
  ensure
    page.driver.browser.delete_network_conditions
  end

  def turbo_visit(path)
    page.execute_script("Turbo.visit(arguments[0])", path)
  end
end

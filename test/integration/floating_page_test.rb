# frozen_string_literal: true

require "test_helper"

# A card, a todo or an event opened in the workspace floats over all the tiles: the
# tool's page in a frame of its own, asked for with ?float, which is drawn as that
# dialog and nothing else (ApplicationController#floating?, services/float.js).
class FloatingPageTest < ActionDispatch::IntegrationTest
  FRAME = { "Sec-Fetch-Dest" => "iframe" }.freeze

  setup do
    sign_in_as users(:one)
  end

  test "a floating board is the card in its dialog, without the board" do
    board = tools(:project_board)
    card = cards(:first_task)

    get tool_board_path(board, card: card.id, float: 1), headers: FRAME

    assert_response :success
    assert_select "[data-controller='board'] dialog#card-detail-modal [data-board-target='cardModal'][data-drawn='#{card.id}']" do
      assert_select "h2", text: "First task"
    end
    assert_select ".board-column", count: 0
    assert_select "h1", count: 0
  end

  test "a floating todo list is the todo in its dialog, without the lists" do
    todos = tools(:my_todos)
    item = todo_items(:pending_one)

    get tool_todo_path(todos, item: item.id, float: 1), headers: FRAME

    assert_response :success
    assert_select "[data-controller='todo'] dialog#item-detail-modal [data-todo-target='itemModal'][data-drawn='#{item.id}']"
    assert_select "dialog#item-detail-modal", text: /Buy groceries/
    assert_select ".todo-list-items", count: 0
  end

  test "a floating calendar is the event in its dialog, without the week" do
    calendar = tools(:my_calendar)
    event = calendars_events(:meeting)

    get tool_calendar_path(calendar, event: event.id, float: 1), headers: FRAME

    assert_response :success
    assert_select "[data-controller='calendar'] dialog#event-details-modal [data-calendar-target='eventModal'][data-drawn='#{event.id}']" do
      assert_select "h3", text: "Team Meeting"
      # In a dialog, so it closes rather than going back to the calendar
      assert_select "button", text: "Close"
    end
    assert_select "#calendar-week-container", count: 0
  end

  test "opening a card that floats reads what there was to read about it" do
    board = tools(:project_board)
    card = cards(:first_task)
    CardAssignmentNotifier.with(card: card, assigner: users(:two), tool: board).deliver(users(:one))

    assert_changes -> { users(:one).notifications.unread.count }, from: 1, to: 0 do
      get tool_board_path(board, card: card.id, float: 1), headers: FRAME
    end
  end

  test "what is gone, or is another tool's, gets the page itself, which says so" do
    board = tools(:project_board)

    get tool_board_path(board, card: 0, float: 1), headers: FRAME
    assert_response :success
    assert_select ".board-column"
    assert_select "[data-board-target='cardModal'][data-drawn]", count: 0

    get tool_todo_path(tools(:my_todos), item: cards(:first_task).id + 10_000, float: 1), headers: FRAME
    assert_response :success
    assert_select "[data-todo-target='itemModal'][data-drawn]", count: 0
  end

  test "only a frame floats: the address in a window of its own is the board" do
    board = tools(:project_board)

    get tool_board_path(board, card: cards(:first_task).id, float: 1)

    assert_response :success
    assert_select ".board-column"
    assert_select "[data-board-target='cardModal'][data-drawn]", count: 0
  end

  test "someone without the tool gets nothing of a card by floating it" do
    sign_in_as users(:two)

    get tool_board_path(tools(:project_board), card: cards(:first_task).id, float: 1), headers: FRAME

    assert_redirected_to root_path
    assert_no_match "First task", response.body
  end
end

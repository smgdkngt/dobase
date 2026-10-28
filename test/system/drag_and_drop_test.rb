# frozen_string_literal: true

require "application_system_test_case"

# Dragging from one place in Dobase onto another (drag_drop_controller.js, Dropped)
class DragAndDropTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a conversation dropped on a folder beside the list moves there" do
    message = mails_messages(:inbox_unread)
    # Folders are a column beside the list from 1440 pixels
    page.driver.browser.manage.window.resize_to(1500, 1000)
    visit tool_mails_path(tools(:my_mail))
    wait_for_stimulus "drag-drop"

    find(".mail-list-item", text: "Welcome to Dobase").drag_to find(".mail-folder-link", text: "Receipts")

    assert_db_change(-> { message.reload.folder == "Receipts" })
    assert_no_selector ".mail-list-item", text: "Welcome to Dobase"
  end

  test "a card dropped on a todo tool in the menu is a todo there" do
    card = cards(:first_task)
    visit tool_board_path(card.column.board.tool)
    wait_for_stimulus "drag-drop"

    find("#board-card-#{card.id}").drag_to find(".sidebar-tool-item[data-tool-id='#{tools(:my_todos).id}']")

    assert_selector ".flash-toast .flash", text: "Added to #{tools(:my_todos).name}"
    assert_db_change(-> { Todos::Item.exists?(title: card.title) })
    assert_equal card.column, card.reload.column, "The card stays where it was"
  end

  test "a todo dropped on a board column is a card in it" do
    item = todo_items(:pending_one)
    visit tool_todo_path(tools(:my_todos))
    wait_for_stimulus "drag-drop"

    # A todo is dragged by its handle
    find("#todo-item-#{item.id}").hover
    find("#todo-item-#{item.id} .todo-drag-handle").drag_to find(".sidebar-tool-item[data-tool-id='#{tools(:project_board).id}']")

    assert_db_change(-> { Boards::Card.exists?(title: item.title) })
  end

  test "a conversation held over the folder picker opens it, and is dropped on a folder in it" do
    message = mails_messages(:inbox_unread)
    visit tool_mails_path(tools(:my_mail))
    wait_for_stimulus "drag-drop"

    row = find(".mail-list-item", text: "Welcome to Dobase")
    picker = find("[popovertarget=mail-folder-menu]")
    # What dragging does, held over the picker until it opens, then dropped on a folder in it
    page.execute_script(<<~JS, row, picker)
      const [ row, picker ] = arguments
      window.transfer = new DataTransfer()
      row.dispatchEvent(new DragEvent("dragstart", { bubbles: true, dataTransfer: window.transfer }))
      window.hold = setInterval(() => picker.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: window.transfer })), 50)
    JS
    assert_selector "#mail-folder-menu:popover-open"
    page.execute_script(<<~JS, find("#mail-folder-menu .dropdown-item", text: "Receipts"))
      clearInterval(window.hold)
      const folder = arguments[0]
      folder.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: window.transfer }))
      folder.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: window.transfer }))
    JS

    assert_db_change(-> { message.reload.folder == "Receipts" })
  end

  test "in the workspace a conversation is dragged from its tile onto a board's column in another" do
    board = tools(:project_board)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(tools(:my_mail)))
    wait_for_stimulus "workspace"
    within(".workspace-hint") { click_on "Got it" }
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(board))
    column = board.board.columns.first
    assert_selector "turbo-frame.tile-frame #column-#{column.id}-cards"

    find("turbo-frame.tile-frame .mail-list-item", text: "Welcome to Dobase").drag_to find("#column-#{column.id}-cards")

    assert_selector "#column-#{column.id}-cards .board-card", text: "Welcome to Dobase"
    assert_current_path workspace_path
  end
end

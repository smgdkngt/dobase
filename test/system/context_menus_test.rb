# frozen_string_literal: true

require "application_system_test_case"

# A right click on what a page is made of offers what can be done to it
# (components/context_menu, context_menu_controller.js)
class ContextMenusTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "a conversation's menu archives it" do
    message = mails_messages(:inbox_unread)
    visit tool_mails_path(tools(:my_mail))

    find(".mail-list-item", text: "Welcome to Dobase").right_click
    find(".context-menu [role=menuitem]", text: /\AArchive\b/).click

    assert_no_selector ".mail-list-item", text: "Welcome to Dobase"
    assert message.reload.archived?
    assert_no_selector ".context-menu"
  end

  test "the menu key opens the menu of what has the keyboard, and Escape closes it" do
    visit tool_mails_path(tools(:my_mail))

    find(".mail-list-item a", text: "Welcome to Dobase").send_keys([ :shift, :f10 ])
    assert_selector ".context-menu [role=menuitem]:focus", text: "Reply"

    send_keys :escape
    assert_no_selector ".context-menu"
  end

  test "a right click in a field or with Shift is the browser's" do
    visit tool_mails_path(tools(:my_mail))

    find(".mail-list-item", text: "Welcome to Dobase").right_click(:shift)
    assert_no_selector ".context-menu"
  end

  test "a card's menu moves it to another column, and the board stays" do
    card = cards(:first_task)
    visit tool_board_path(card.column.board.tool)

    find("#board-card-#{card.id}").right_click
    target = (card.column.board.columns - [ card.column ]).first
    find(".context-menu [role=menuitem]", text: "Move to #{target.name}").click

    assert_selector "#column-#{target.id}-cards #board-card-#{card.id}"
    assert_equal target, card.reload.column
    assert_no_selector "dialog[open]"
  end

  test "a todo's menu moves it to another list" do
    item = todo_items(:pending_one)
    visit tool_todo_path(tools(:my_todos))

    find("#todo-item-#{item.id}").right_click
    find(".context-menu [role=menuitem]", text: "Move to Backlog").click

    assert_selector "#todo-item-#{item.id}"
    assert_db_change(-> { item.reload.list == todo_lists(:backlog) })
  end

  test "a chat message's menu offers editing only for your own" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |t| t.name = "Chat"; t.icon = "message-circle"; t.enabled = true }
    tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    tool.collaborators.create!(user: users(:two), role: "collaborator")
    mine = tool.chat.messages.create!(user: @user, body: "Mine")
    theirs = tool.chat.messages.create!(user: users(:two), body: "Theirs")
    visit tool_chat_path(tool)

    find("##{ActionView::RecordIdentifier.dom_id(theirs)}").right_click
    within(".context-menu") do
      assert_selector "[role=menuitem]", text: "Reply"
      assert_no_selector "[role=menuitem]", text: "Edit"
    end
    send_keys :escape

    find("##{ActionView::RecordIdentifier.dom_id(mine)}").right_click
    within(".context-menu") { assert_selector "[role=menuitem]", text: "Edit" }
    find(".context-menu [role=menuitem]", text: "Delete").click
    within("dialog#turbo-confirm-dialog[open]") { click_on "Delete" }

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(mine)}"
  end

  test "a tool's menu in the sidebar mutes its notifications" do
    tool = tools(:my_todos)
    visit tool_todo_path(tool)

    find(".sidebar-tool-item[data-tool-id='#{tool.id}']").right_click
    find(".context-menu [role=menuitem]", text: "Mute notifications").click

    assert_db_change(-> { tool.muted_by?(@user) })
  end

  test "a document's menu deletes it, after asking" do
    document = docs_documents(:meeting_notes)
    visit tool_docs_path(document.tool)

    find("[data-document-id='#{document.id}']").right_click
    find(".context-menu [role=menuitem]", text: "Delete").click
    within("dialog#turbo-confirm-dialog[open]") { click_on "Delete" }

    assert_no_selector "[data-document-id='#{document.id}']"
    assert_not Docs::Document.exists?(document.id)
  end

  test "an appointment's menu opens it" do
    event = Calendars::Event.find_by!(uid: "meeting-123@dobase")
    visit tool_calendar_path(tools(:my_calendar), week_start: event.starts_at.to_date.iso8601)

    find("[data-event-id='#{event.id}']", match: :first).right_click
    find(".context-menu [role=menuitem]", text: "Edit").click

    assert_current_path edit_tool_calendar_event_path(tools(:my_calendar), event)
  end
end

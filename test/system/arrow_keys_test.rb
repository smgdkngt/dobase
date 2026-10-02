# frozen_string_literal: true

require "application_system_test_case"

# The arrow keys go through what a page is made of (arrow_keys_controller.js): every
# tool can be worked without the mouse.
class ArrowKeysTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "a board: from card to card, into one, and a card moved to the next column" do
    board = tools(:project_board)
    visit tool_board_path(board)
    wait_for_stimulus "arrow-keys"

    press :arrow_down
    assert_focused "#board-card-#{cards(:first_task).id}"
    press :arrow_down
    assert_focused "#board-card-#{cards(:second_task).id}"
    press :arrow_right
    assert_focused "#board-card-#{cards(:third_task).id}"
    press :arrow_left
    assert_focused "#board-card-#{cards(:first_task).id}"

    press :enter
    assert_selector "dialog#card-detail-modal[open] h2", text: "First task"
    # In the dialog the arrows are the dialog's, not the board's behind it
    press :arrow_down
    assert_selector "dialog#card-detail-modal[open]"
    press :escape
    assert_focused "#board-card-#{cards(:first_task).id}"

    press [ :shift, :arrow_right ]
    assert_selector "#column-#{cards(:third_task).column_id}-cards #board-card-#{cards(:first_task).id}"
    assert_focused "#board-card-#{cards(:first_task).id}"
    assert_db_change -> { cards(:first_task).reload.column_id == cards(:third_task).column_id }
  end

  test "todos: from item to item, to its checkbox, and an item moved up" do
    visit tool_todo_path(tools(:my_todos))
    wait_for_stimulus "arrow-keys"
    first, second = todo_items(:pending_one), todo_items(:pending_two)

    press :arrow_down
    assert_equal "Open #{first.title}", focused_label
    press :arrow_down
    assert_equal "Open #{second.title}", focused_label
    press :arrow_left
    assert_focused "#todo-item-#{second.id}-completion"
    press :arrow_right

    press [ :shift, :arrow_up ]
    assert_equal "Open #{second.title}", focused_label
    assert_db_change -> { second.reload.position < first.reload.position }
  end

  test "docs: from document to document, into one and back out with the left arrow" do
    docs = tools(:my_docs)
    visit tool_docs_path(docs)
    wait_for_stimulus "arrow-keys"

    press :arrow_down
    opened = page.evaluate_script("document.activeElement.getAttribute('href')")
    assert_match %r{/docs/documents/\d+}, opened
    press :enter
    assert_current_path opened

    press :arrow_left
    assert_current_path tool_docs_path(docs)
  end

  test "files: into a folder and back up with the left arrow" do
    files = tools(:my_files)
    visit tool_files_path(files)
    wait_for_stimulus "arrow-keys"

    press :arrow_right
    assert_equal "Folder #{file_folders(:documents).name}", focused_label
    press :enter
    assert_current_path tool_files_path(files, folder_id: file_folders(:documents).id)
    assert_text file_folders(:nested_folder).name

    press :arrow_left
    assert_current_path tool_files_path(files)
  end

  test "chat: up from an empty message box into the messages, and down back to it" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |t| t.name = "Chat"; t.icon = "message-circle"; t.enabled = true }
    chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    chat.chat.messages.create!(user: @user, body: "First")
    last = chat.chat.messages.create!(user: @user, body: "Second")
    visit tool_chat_path(chat)
    wait_for_stimulus "chat"

    find("rhino-editor [contenteditable]").click
    press :arrow_up
    assert_focused "##{ActionView::RecordIdentifier.dom_id(last)}"
    press :arrow_up
    assert_selector ":focus", text: "First"

    press "r"
    assert_selector "[data-chat-target='replyPreview']", text: "First"
    assert_selector "rhino-editor [contenteditable]:focus"

    press :arrow_up
    press :arrow_down
    assert_selector "rhino-editor [contenteditable]:focus"
  end

  test "the calendar: from event to event, and past the week to the next one" do
    calendar = tools(:my_calendar)
    visit tool_calendar_path(calendar)
    wait_for_stimulus "arrow-keys"
    week = page.evaluate_script("document.querySelector('[data-calendar-week-start-value]').dataset.calendarWeekStartValue")

    # Until the week changes, and not a press further: those would be the next week's.
    # A press either moves to another event or, past the last one, brings the next week.
    this_week = "[data-calendar-week-start-value='#{week}']"
    12.times do
      before = page.evaluate_script("document.activeElement.dataset.eventId || ''")
      press :arrow_right
      gone = page.document.synchronize(5) do
        gone = page.has_no_selector?(this_week, wait: 0)
        raise Capybara::ExpectationNotMet, "the key did nothing yet" unless gone || page.evaluate_script("document.activeElement.dataset.eventId || ''") != before
        gone
      end
      break if gone
    end

    assert_no_selector "[data-calendar-week-start-value='#{week}']"
    assert_selector "[data-calendar-week-start-value='#{(Date.parse(week) + 7).iso8601}']"
  end

  test "mail: down the list, each conversation opening beside it" do
    mail = tools(:my_mail)
    visit tool_mails_path(mail)
    wait_for_stimulus "mail-keyboard"

    press :arrow_down
    assert_selector ".mail-list-item.selected", count: 1
    first = find(".mail-list-item.selected")[:id]
    assert_selector ".mail-detail-header"

    press :arrow_down
    assert_no_selector "##{first}.selected"
    assert_selector ".mail-list-item.selected", count: 1

    # The keys dialog lies over the mail: the arrows are its own, to scroll with
    second = find(".mail-list-item.selected")[:id]
    press "?"
    assert_selector "dialog[open]", text: "Keyboard shortcuts"
    press :arrow_down
    press :escape
    assert_selector "##{second}.selected"
  end

  test "the arrows are left alone while you type" do
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "arrow-keys"

    find("[data-board-target='addCardBtn']", match: :first).click
    field = find("textarea[data-board-target='addCardInput']", match: :first)
    field.send_keys("New card", :arrow_left, :arrow_down)

    assert_equal field.native, page.driver.browser.switch_to.active_element
    assert_equal "New card", field.value
  end

  private

  # To whatever has the keyboard, as a person's keys go
  def press(keys)
    chain = page.driver.browser.action
    keys = Array(keys)
    keys[0..-2].each { |modifier| chain.key_down(modifier) }
    chain.send_keys(keys.last)
    keys[0..-2].reverse_each { |modifier| chain.key_up(modifier) }
    chain.perform
  end

  def assert_focused(selector)
    assert_selector "#{selector}:focus"
  end

  def focused_label
    page.document.synchronize do
      label = page.evaluate_script("document.activeElement.getAttribute('aria-label')")
      raise Capybara::ExpectationNotMet, "nothing with a label has the keyboard" if label.blank?
      label
    end
  end
end

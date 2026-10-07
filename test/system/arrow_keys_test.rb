# frozen_string_literal: true

require "application_system_test_case"

# The arrow keys go through what a page is made of (arrow_keys_controller.js): every
# tool can be worked without the mouse.
class ArrowKeysTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "what the keyboard is on is marked for the styles, since Safari draws no focus mark on what a script focused" do
    board = tools(:project_board)
    visit tool_board_path(board)
    wait_for_stimulus "arrow-keys"

    press :arrow_down
    assert_selector "#board-card-#{cards(:first_task).id}[data-keyboard-focus]"
    press :arrow_down
    assert_selector "#board-card-#{cards(:second_task).id}[data-keyboard-focus]"
    # The mark goes with the keyboard, and a click leaves none
    assert_no_selector "#board-card-#{cards(:first_task).id}[data-keyboard-focus]"
    find("h1", text: board.name).click
    assert_no_selector "[data-keyboard-focus]"

    # A conversation in mail: the row is the mark, with no ring of the link's own inside it
    mail = tools(:my_mail)
    visit tool_mails_path(mail)
    wait_for_stimulus "arrow-keys"
    press :arrow_down
    row = "document.activeElement.closest('.mail-list-item')"
    assert page.evaluate_script("#{row} !== null && document.activeElement.hasAttribute('data-keyboard-focus')")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.activeElement).boxShadow")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.activeElement).outlineStyle")
    selected = page.evaluate_script("getComputedStyle(document.querySelector('.mail-list-item:not(:has(a:focus))')).backgroundColor")
    assert_not_equal selected, page.evaluate_script("getComputedStyle(#{row}).backgroundColor")
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

  test "a board: Home and End go to the top and the bottom of the column, and c adds a card to it" do
    board = tools(:project_board)
    visit tool_board_path(board)
    wait_for_stimulus "arrow-keys"

    press :arrow_down
    assert_focused "#board-card-#{cards(:first_task).id}"
    press :end
    # The last thing in the column is its "Add card"
    assert_selector "[data-board-target='addCardBtn'][data-column-id='#{cards(:first_task).column_id}']:focus"
    press :home
    assert_focused "#board-card-#{cards(:first_task).id}"

    press :arrow_right
    assert_focused "#board-card-#{cards(:third_task).id}"
    press "c"
    assert_selector "textarea[data-board-target='addCardInput'][data-column-id='#{cards(:third_task).column_id}']:focus"
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

    # The space bar ticks the todo you are on; Enter is what opens it
    press :space
    assert_db_change -> { second.reload.completed? }
    assert_no_selector "dialog#item-detail-modal[open]"
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

    # Back in the list, the first arrow lands on the document you left it by
    wait_for_turbo
    wait_for_stimulus "arrow-keys"
    press :arrow_down
    assert_selector "a[href='#{opened}']:focus"
  end

  test "docs: the place in the list is kept, wherever it was" do
    docs = tools(:my_docs)
    visit tool_docs_path(docs)
    wait_for_stimulus "arrow-keys"

    press :arrow_down
    press :arrow_right
    second = page.evaluate_script("document.activeElement.getAttribute('href')")
    press :enter
    assert_current_path second
    press :arrow_left
    assert_current_path tool_docs_path(docs)
    wait_for_turbo
    wait_for_stimulus "arrow-keys"

    press :arrow_down
    assert_selector "a[href='#{second}']:focus"
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

  test "files: the space bar picks the file you are on, beside what is picked" do
    visit tool_files_path(tools(:my_files))
    wait_for_stimulus "arrow-keys"

    press :arrow_right
    press :space
    assert_selector "[data-file-selection-target='item'].ring-accent", count: 1
    press :arrow_right
    press :space
    assert_selector "[data-file-selection-target='item'].ring-accent", count: 2
    press :space
    assert_selector "[data-file-selection-target='item'].ring-accent", count: 1
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
    # The week the meeting is in: tomorrow, which on a Sunday is next week
    visit tool_calendar_path(calendar, week_start: Calendars::Event.find_by!(uid: "meeting-123@dobase").starts_at.to_date.iso8601)
    wait_for_stimulus "arrow-keys"
    week = page.evaluate_script("document.querySelector('[data-calendar-week-start-value]').dataset.calendarWeekStartValue")

    # Until the week changes, and not a press further: those would be the next week's.
    # A press either moves on (to another event, or from the last one to the
    # buttons above the week, which have no event to tell them apart by) or,
    # past the last thing, brings the next week.
    this_week = "[data-calendar-week-start-value='#{week}']"
    20.times do
      page.execute_script("window.__before = document.activeElement")
      press :arrow_right
      gone = page.document.synchronize(5) do
        gone = page.has_no_selector?(this_week, wait: 0)
        raise Capybara::ExpectationNotMet, "the key did nothing yet" unless gone || page.evaluate_script("document.activeElement !== window.__before")
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

    press_and_wait_for_the_conversation :arrow_down
    assert_selector ".mail-list-item.selected", count: 1
    first = find(".mail-list-item.selected")[:id]
    assert_selector ".mail-detail-header"

    press_and_wait_for_the_conversation :arrow_down
    assert_no_selector "##{first}.selected"
    assert_selector ".mail-list-item.selected", count: 1

    # The keys dialog lies over the mail: the arrows are its own, to scroll with
    second = find(".mail-list-item.selected")[:id]
    press "?"
    assert_selector "dialog[open]", text: "Keyboard shortcuts"
    press :arrow_down
    press :escape
    assert_selector "##{second}.selected"

    # To the right of the list is the message: its buttons are gone through like anything else
    press :arrow_right
    assert page.evaluate_script("document.getElementById('mail-content').contains(document.activeElement)"), "the keyboard went into the message"
    press :arrow_left
    assert_selector "##{second} a:focus"

    # Enter presses what has the keyboard, a folder as well as a conversation
    find("button[popovertarget='mail-folder-menu']").click
    assert_selector "#mail-folder-menu a:focus"
    press :arrow_down
    folder = page.evaluate_script("document.activeElement.getAttribute('href')")
    press :enter
    assert_current_path folder
    wait_for_stimulus "mail-keyboard"
    visit tool_mails_path(mail)
    wait_for_stimulus "mail-keyboard"
    press_and_wait_for_the_conversation :arrow_down
    first = find(".mail-list-item.selected")[:id]

    # End and Home: the last conversation and the first
    press_and_wait_for_the_conversation :end
    assert_selector ".mail-list-item:last-child.selected"
    press_and_wait_for_the_conversation :home
    assert_selector "##{first}.selected"
  end

  test "a dialog scrolls with the arrows, the page under it stays as it is" do
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "arrow-keys"
    page.driver.browser.manage.window.resize_to(1400, 500)

    press "?"
    assert_selector "dialog[open]", text: "Keyboard shortcuts"
    scroller = "document.querySelector('dialog[open] .modal-body')"
    assert_equal 0, page.evaluate_script("#{scroller}.scrollTop")

    3.times { press :arrow_down }
    assert_operator page.evaluate_script("#{scroller}.scrollTop"), :>, 100
    press :end
    assert page.evaluate_script("#{scroller}.scrollTop + #{scroller}.clientHeight >= #{scroller}.scrollHeight - 2")
    assert_no_selector ".board-card:focus"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "in a dialog the arrows go through what takes the keyboard: tabs, fields, buttons" do
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "arrow-keys"

    find(".sidebar-user-btn").click
    # The menu that opened has the keyboard on its first entry
    assert_selector "#sidebar-user-menu button:focus", text: "Profile"
    press :enter

    within "dialog#profile-modal[open]" do
      assert_selector "[data-tabs-target='tab'][data-tab='profile']"
      find("[data-tabs-target='tab'][data-tab='profile']").send_keys(:arrow_down)
      assert_selector "[data-tabs-target='tab'][data-tab='appearance']:focus"
      press :enter
      assert_selector ".theme-option", minimum: 3

      # Into the grid of themes and through it
      press :arrow_right
      assert_selector ".theme-option:focus"
      first = page.evaluate_script("document.activeElement.value")
      press :arrow_right
      assert_not_equal first, page.evaluate_script("document.activeElement.value")
      assert_selector ".theme-option:focus"
    end
    # Nothing behind the dialog was reached
    assert_no_selector ".board-card:focus"
    assert_current_path tool_board_path(tools(:project_board))
  end

  test "from a one-line field in a dialog, down goes on to what is under it" do
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "arrow-keys"

    press "n"
    within "dialog[id^='add-column-modal'][open]" do
      field = find("input[type='text']", match: :first)
      field.send_keys("Later")
      press :arrow_down
      assert_selector "button:focus"
      assert_equal "Later", field.value
    end
  end

  test "the menu: a tool's settings are one arrow to the right of it" do
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "arrow-keys"

    find("[data-sidebar-tool-link]", match: :first).send_keys(:arrow_right)
    assert_selector ".sidebar-tool-menu-btn:focus"
    press :enter
    assert_selector "dialog#edit-tool-modal[open]"
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

  # A conversation that opens beside the list becomes the page's address a moment
  # after it shows. That is a visit, and a visit closes whatever dialog is open
  # (modal_controller.js): nothing that opens one is pressed until it is over.
  def press_and_wait_for_the_conversation(key)
    page.execute_script("window.__arrived = false; document.addEventListener('turbo:load', () => { window.__arrived = true }, { once: true })")
    press key
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "the conversation hasn't arrived" unless page.evaluate_script("window.__arrived")
    end
    wait_for_turbo
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

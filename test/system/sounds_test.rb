# frozen_string_literal: true

require "application_system_test_case"

# The app's sounds (services/sound.js). A test can't hear, so it listens for the
# "sound:played" event the service sends for every sound it starts.
class SoundsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |t| t.name = "Chat"; t.icon = "message-circle"; t.enabled = true }
    @chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    sign_in_as(@user)
  end

  test "a message you send is heard, and so is one that arrives, but not your own coming back" do
    colleague = users(:two)
    @chat.collaborators.create!(user: colleague, role: "collaborator")
    visit tool_chat_path(@chat)
    wait_for_stimulus "chat"
    listen

    type_message "Lunch?"
    assert_heard "send"
    # The message itself comes back over the stream, as it does for everyone: that is not news
    assert_selector ".chat-message", text: "Lunch?"
    assert_equal %w[send], heard

    @chat.chat.messages.create!(user: colleague, body: "<p>Pizza</p>")
    assert_selector ".chat-message", text: "Pizza"
    assert_heard "receive"
    assert_equal %w[send receive], heard
  end

  test "a todo ticked off is heard, and one unticked is not" do
    todos = tools(:my_todos)
    item = todo_items(:pending_one)
    visit tool_todo_path(todos)
    wait_for_stimulus "todo"
    listen

    find("#todo-item-#{item.id}-completion").click
    # Heard at the click, before the server has answered
    assert_heard "done"
    assert_selector "#todo-item-#{item.id}.todo-item-completed"

    find("#todo-item-#{item.id}-completion").click
    assert_no_selector "#todo-item-#{item.id}.todo-item-completed"
    assert_equal %w[done], heard
  end

  test "a notification about a tool you aren't looking at is heard; a new chat message in the chat you are in is not heard twice" do
    colleague = users(:two)
    visit tool_chat_path(@chat)
    wait_for_stimulus "notifications"
    # The page has to be touched before a browser lets it make sound
    find("rhino-editor .ProseMirror").click
    listen

    perform_enqueued_jobs do
      CardAssignmentNotifier.with(card: cards(:first_task), assigner: colleague, tool: tools(:project_board)).deliver(@user)
    end
    assert_heard "notify"

    @chat.collaborators.create!(user: colleague, role: "collaborator")
    perform_enqueued_jobs { @chat.chat.messages.create!(user: colleague, body: "<p>Here</p>") }
    assert_selector ".chat-message", text: "Here"
    assert_heard "receive"
    assert_equal %w[notify receive], heard
  end

  test "mail is heard when the mail server has taken it, not when Send is pressed" do
    mail = tools(:my_mail)
    visit new_tool_mail_path(mail, reply_to: mails_messages(:inbox_read).id, folder: "inbox")
    assert_selector "rhino-editor [contenteditable]"
    find("rhino-editor [contenteditable]").send_keys("Thanks for these")
    listen

    click_on "Send"
    assert_selector "[data-controller~='mail-sending']", text: "Sending…"
    assert_empty heard

    capture_smtp_deliveries { perform_enqueued_jobs(only: SendMailJob) }
    assert_no_selector "[data-controller~='mail-sending']", wait: 10
    assert_heard "sent"
  end

  test "sounds can be switched off for this browser, and every one of them can be tried" do
    visit edit_profile_path(tab: "notifications")
    wait_for_stimulus "sounds"
    listen

    assert find("[data-sounds-target='on']").checked?
    names = all("[data-action='sounds#hear']").map do |button|
      button.click
      button["data-sounds-name-param"]
    end
    assert_operator names.size, :>=, 10
    assert_heard(*names)

    uncheck "Play sounds"
    visit tool_chat_path(@chat)
    wait_for_stimulus "chat"
    listen
    type_message "Quietly"
    assert_selector ".chat-message", text: "Quietly"
    assert_empty heard

    # Still off after loading the app again, and the previews work regardless
    visit edit_profile_path(tab: "notifications")
    wait_for_stimulus "sounds"
    listen
    assert_not find("[data-sounds-target='on']").checked?
    first("[data-action='sounds#hear']").click
    assert_heard "send"

    check "Play sounds"
    assert_heard "send", "done"
  end

  private

  def listen
    page.execute_script(<<~JS)
      window.heardSounds = []
      if (!window.listeningForSounds) document.addEventListener("sound:played", (event) => window.heardSounds.push(event.detail.name))
      window.listeningForSounds = true
    JS
  end

  def heard
    page.evaluate_script("window.heardSounds")
  end

  def assert_heard(*names)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "expected to hear #{names.inspect}, heard #{heard.inspect}" unless heard.last(names.size) == names
    end
  end

  def type_message(text)
    editable = find("rhino-editor .ProseMirror")
    editable.click
    editable.send_keys(text, :enter)
  end
end

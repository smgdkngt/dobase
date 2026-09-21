# frozen_string_literal: true

require "application_system_test_case"

class ChatTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |t| t.name = "Chat"; t.icon = "message-circle"; t.enabled = true }
    @tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    sign_in_as(@user)
  end

  test "a message broadcast from someone in another time zone shows the time in the viewer's zone" do
    @user.update!(timezone: "Tokyo")
    sent_at = 1.hour.ago.change(sec: 0)
    message = Time.use_zone("UTC") { @tool.chat.messages.create!(user: @user, body: "From London", created_at: sent_at) }

    visit tool_chat_path(@tool)
    wait_for_stimulus "local-time"
    # What the sender's request renders and broadcasts: the time in the sender's zone
    rendered = Time.use_zone("UTC") { ApplicationController.render(partial: "tools/chats/message", locals: { message: message }) }
    page.execute_script(<<~JS, rendered)
      const template = document.createElement("template")
      template.innerHTML = arguments[0].replace('id="', 'id="broadcast_')
      document.getElementById("chat_messages").append(template.content)
    JS

    within("[id^='broadcast_']") { assert_selector "time", text: sent_at.in_time_zone("Tokyo").strftime("%-I:%M %p") }
  end

  test "a picked file shows its size the way the rest of the app does" do
    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    path = File.join(Dir.mktmpdir, "notes.txt").tap { |file| File.write(file, "a" * 2048) }
    find("[data-chat-target='fileInput']", visible: :all).attach_file(path, make_visible: true)

    assert_selector "[data-filesize]", text: "2 KB"
  end

  test "an empty message can't be sent" do
    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    assert_no_difference -> { Chats::Message.count } do
      find("button[type=submit][title='Send message'], form.chat-form button[type=submit]", match: :first).click
      sleep 0.5
    end
  end

  test "the / shortcut focuses the message editor" do
    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"
    assert_selector "rhino-editor"

    find("body").send_keys("/")
    sleep 0.3

    focused_in_editor = page.evaluate_script(<<~JS)
      !!document.activeElement.closest(".ProseMirror")
    JS
    assert focused_in_editor, "expected the editor to be focused after '/'"
  end

  test "disconnecting the chat controller removes its window focus listener" do
    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    page.execute_script(<<~JS)
      window.__reads = 0
      const original = window.fetch
      window.fetch = (...args) => { if (String(args[0]).includes('/read')) window.__reads++; return original(...args) }
    JS

    # A bare arrow function passed straight to addEventListener (the bug)
    # can never be removed — disconnect()'s removeEventListener call is a
    # no-op for it, so the listener silently keeps firing after disconnect.
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller~='chat']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "chat")
      controller.disconnect()
    JS
    page.execute_script("window.dispatchEvent(new Event('focus'))")
    sleep 0.5

    assert_equal 0, page.evaluate_script("window.__reads"),
      "a focus event after disconnect() must not still trigger markAsRead"
  end

  test "the error slot survives being cleared, so a later failed send still shows its error" do
    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    submit_blank_body
    assert_selector "#chat-form-errors", text: "can't be blank", wait: 5

    fill_in_editor("Hello there")
    click_send
    assert_no_text "can't be blank"
    assert_text "Hello there"

    submit_blank_body
    assert_selector "#chat-form-errors", text: "can't be blank", wait: 5
  end

  test "an owner is offered someone else's message to delete" do
    other = users(:two)
    @tool.collaborators.create!(user: other, role: "collaborator")
    @tool.chat.messages.create!(user: other, body: "Not mine")

    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    assert_selector "[data-message-delete]:not(.hidden)", visible: :all, wait: 5
  end

  test "a collaborator is not offered someone else's message to delete" do
    other = users(:two)
    theirs = Tool.create!(name: "Their Chat", tool_type: @tool.tool_type, owner: other)
    theirs.collaborators.create!(user: @user, role: "collaborator")
    theirs.chat.messages.create!(user: other, body: "Not mine")

    visit tool_chat_path(theirs)
    wait_for_turbo
    wait_for_stimulus "chat"

    assert_text "Not mine"
    assert_selector "[data-message-delete].hidden", visible: :all
  end

  test "reaching the top of the chat loads older messages and keeps the reader's place" do
    (Chats::Chat::MESSAGES_PER_PAGE + 5).times do |index|
      @tool.chat.messages.create!(user: @user, body: "<p>Message #{index}</p>")
    end

    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    assert_text "Message #{Chats::Chat::MESSAGES_PER_PAGE + 4}"
    assert_no_text "Message 0"

    page.execute_script("document.querySelector(\"[data-chat-target='messages']\").scrollTop = 0")

    assert_text "Message 0", wait: 5
    scroll_top = page.evaluate_script("document.querySelector(\"[data-chat-target='messages']\").scrollTop")
    assert scroll_top > 0,
      "expected the older messages to go in above the reader, not to drop them at the top of the chat"
  end

  test "an author rewrites their own message from the page, and it says it was edited" do
    @tool.chat.messages.create!(user: @user, body: "<p>Tpyo</p>")

    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"
    assert_text "Tpyo"

    # The actions come up under the pointer, and only for the author once the
    # message's own controller has connected.
    wait_for_stimulus "message"
    find("[data-message-id]", match: :first).hover
    find("[data-message-edit] a", visible: :all).execute_script("this.click()")
    assert_selector "turbo-frame[id^='body_chats_message'] rhino-editor", wait: 5

    within("turbo-frame[id^='body_chats_message']") do
      fill_in_editor "Fixed"
      click_button "Save"
    end

    assert_text "Fixed"
    assert_no_text "Tpyo"
    assert_selector "[data-message-edited]", text: "edited"
  end

  test "someone else's message is not offered for editing" do
    other = users(:two)
    @tool.collaborators.create!(user: other, role: "collaborator")
    @tool.chat.messages.create!(user: other, body: "<p>Not mine</p>")

    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"

    assert_text "Not mine"
    assert_selector "[data-message-edit].hidden", visible: :all
  end

  private

  # Submits a genuinely blank body straight to the server (bypassing the
  # client-side isEmpty guard, which is exercised separately by "an empty
  # message can't be sent") and applies whatever turbo-stream comes back,
  # exactly like a real failed form submission would.
  def submit_blank_body
    # allow_forgery_protection is off in the test environment, so no CSRF
    # token is needed here (there's no csrf-token meta tag to read).
    page.execute_script(<<~JS)
      fetch(window.location.pathname + "/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: "message%5Bbody%5D="
      }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
    JS
    sleep 0.3
  end

  # Clears through the editor the caret is actually in — the page can hold more
  # than one (the compose box and a message being rewritten).
  def fill_in_editor(text)
    editable = find("rhino-editor .ProseMirror")
    editable.click
    page.execute_script(<<~JS, editable)
      arguments[0].closest("rhino-editor").editor.commands.clearContent()
    JS
    editable.send_keys(text)
  end

  def click_send
    find("form.chat-form button[type=submit], button[type=submit][title='Send message']", match: :first).click
    wait_for_turbo
    sleep 0.3
  end

  test "an emoji put on a message shows for everyone, marked as yours for you" do
    colleague = users(:two)
    @tool.collaborators.create!(user: colleague, role: "collaborator")
    message = @tool.chat.messages.create!(user: colleague, body: "Standup at 2?")

    visit tool_chat_path(@tool)
    wait_for_stimulus "reactions"
    assert_no_text "No messages yet"

    within("##{ActionView::RecordIdentifier.dom_id(message)}") do
      # The hover bar is see-through until the pointer is on the message
      find("[title='Add a reaction']", visible: :all).execute_script("this.click()")
      find("[aria-label='React with 👍']").click
      assert_selector ".chat-reaction[aria-pressed='true']", text: /👍\s+1/
    end

    # A colleague's emoji arrives over the broadcast, and isn't marked as yours
    message.reactions.create!(user: colleague, emoji: "🎉")
    within("##{ActionView::RecordIdentifier.dom_id(message)}") do
      assert_selector ".chat-reaction[aria-pressed='false']", text: /🎉\s+1/

      find(".chat-reaction", text: "👍").click
      assert_no_selector ".chat-reaction", text: "👍"
    end
  end
end

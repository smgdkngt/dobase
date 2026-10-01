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

  test "what arrives leaves a reader who scrolled up where they are, and their own message brings them back" do
    colleague = users(:two)
    @tool.collaborators.create!(user: colleague, role: "collaborator")
    messages = 30.times.map do |index|
      @tool.chat.messages.create!(user: colleague, body: "<p>Message #{index}</p><p>with</p><p>more lines</p>")
    end

    visit tool_chat_path(@tool)
    wait_for_turbo
    wait_for_stimulus "chat"
    assert_text "Message 29"
    assert_operator chat_scroll_top, :>, 200, "the chat should be long enough to scroll"

    # At the newest message, the reader follows what arrives
    @tool.chat.messages.create!(user: colleague, body: "<p>Lunch?</p>")
    assert_text "Lunch?"
    assert_at_newest_message

    scroll_chat_to 100
    messages.last.reactions.create!(user: colleague, emoji: "🎉")
    assert_selector ".chat-reaction", text: "🎉"
    messages.last.update!(body: "<p>Rewritten</p>")
    assert_text "Rewritten"
    messages.first.destroy!
    assert_no_text "Message 0"
    ChatChannel.typing(@tool.chat, colleague)
    assert_text "#{colleague.name} is typing..."
    @tool.chat.messages.create!(user: colleague, body: "<p>Pizza</p>")
    assert_text "Pizza"
    # Scrolling to the newest message happened a moment after each of those
    sleep 0.3
    assert_operator chat_distance_from_newest, :>, 200, "the reader was taken to the newest message"

    fill_in_editor "Fine by me"
    click_send
    assert_text "Fine by me"
    assert_at_newest_message
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

  def chat_scroll_top
    evaluate_script("document.querySelector(\"[data-chat-target='messages']\").scrollTop")
  end

  def chat_distance_from_newest
    evaluate_script(<<~JS)
      (() => {
        const list = document.querySelector("[data-chat-target='messages']")
        return list.scrollHeight - list.scrollTop - list.clientHeight
      })()
    JS
  end

  def assert_at_newest_message
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "the chat isn't at its newest message" unless chat_distance_from_newest < 5
    end
  end

  def scroll_chat_to(top)
    execute_script("document.querySelector(\"[data-chat-target='messages']\").scrollTop = #{top}")
  end

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

  test "on a phone a message's text runs the width of the row, and a closed emoji picker takes no taps" do
    @tool.chat.messages.create!(user: @user, body: "<p>#{"A long enough message to wrap on a phone. " * 4}</p>")
    page.driver.browser.manage.window.resize_to(390, 844)

    visit tool_chat_path(@tool)
    wait_for_stimulus "reactions"
    assert_text "A long enough message"

    # The hidden actions used to sit in the row, and took a third of it from the text
    row, text = page.evaluate_script(<<~JS)
      (() => {
        const message = document.querySelector(".chat-message")
        return [message.getBoundingClientRect().right, message.querySelector(".chat-message-text").getBoundingClientRect().right]
      })()
    JS
    assert_operator row - text, :<, 24, "the text stops #{(row - text).round}px short of the row's edge"

    # A picker that is laid out while closed sits over the messages, see-through, and reacts to a tap
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.chat-reaction-picker')).display")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.chat-message-actions')).pointerEvents")
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
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

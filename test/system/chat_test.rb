# frozen_string_literal: true

require "application_system_test_case"

class ChatTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |t| t.name = "Chat"; t.icon = "message-circle"; t.enabled = true }
    @tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    sign_in_as(@user)
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

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end

# frozen_string_literal: true

require "application_system_test_case"

# A mention, a search hit or a copied link leads to the message itself
# (?message=, chat_controller.js#showFound): the chat opens on it, however far back
# it is, and lights it up for a moment.
class ChatFoundMessageTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  CHAT = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @user = users(:one)
    @colleague = users(:two)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.assign_attributes(name: "Chat", icon: "message-circle", enabled: true) }
    @tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    @tool.collaborators.create!(user: @colleague, role: "collaborator")
    @chat = @tool.chat

    @found = @chat.messages.create!(user: @colleague, body: "The label goes on the left", created_at: 3.hours.ago)
    # Far more after it than a page holds (written in one go: each would tell everyone)
    now = Time.current
    ::Chats::Message.insert_all(230.times.map { |i| { chat_id: @chat.id, user_id: @colleague.id, created_at: (170 - i * 0.5).minutes.ago, updated_at: now } })
    ActionText::RichText.insert_all(@chat.messages.where.not(id: @found.id).pluck(:id).map { |id|
      { record_type: "Chats::Message", record_id: id, name: "body", body: "<p>Later message #{id}</p>", created_at: now, updated_at: now }
    })
    @newest = @chat.messages.create!(user: @colleague, body: "Newest of all")
  end

  test "the chat opens on the message, lit up, with a way back to the newest" do
    sign_in_as @user
    visit tool_chat_path(@tool, message: @found.id)
    wait_for_stimulus "chat"

    message = "[data-message-id='#{@found.id}']"
    assert_selector "#{message}[data-found]"
    assert in_sight?(message), "the message is in sight"
    # Found once: a reload opens the chat at its newest
    assert_current_path tool_chat_path(@tool)
    assert_no_text "Newest of all"
    # The light goes out again
    assert_no_selector "#{message}[data-found]", wait: 5

    click_on "Jump to newest"

    # A page of 200 messages drawn again: on a busy CI runner that took longer than the
    # usual wait once, while the page was right (its screenshot had the newest in sight)
    assert_text "Newest of all", wait: 15
    assert_no_selector message
    assert_no_selector ".chat-jump-newest"
  end

  test "an open chat tile goes to the message, and lights it up" do
    sign_in_as @user
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(@tool))
    wait_for_stimulus "workspace"
    assert_selector "#{CHAT} .chat-messages", text: "Newest of all"
    within(".workspace-hint") { click_on "Got it" }

    # As a notification or the menu's search does: a visit from the workspace's page
    page.execute_script("Turbo.visit(arguments[0])", tool_chat_path(@tool, message: @found.id))

    # The tile loads the chat around the message first; slow on a busy runner (see above)
    assert_selector "#{CHAT} [data-message-id='#{@found.id}'][data-found]", wait: 15
    assert_selector TILE, count: 1
    assert in_sight?("#{CHAT} [data-message-id='#{@found.id}']"), "the message is in sight in the tile"
    assert_current_path workspace_path, ignore_query: true

    # The tile's address is the chat's own again: kept, it opens at the newest next time
    assert_db_change -> {
      urls = WorkspaceLayout.find_by(user: @user)&.state.to_h.fetch("tiles", {}).values.map { |tile| tile["url"] }
      urls.include?(tool_chat_path(@tool)) && urls.none? { |url| url.include?("message=") }
    }
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{CHAT} .chat-messages", text: "Newest of all"
    assert_no_selector "#{CHAT} [data-found]"
  end

  private

  # Inside the list's visible part
  def in_sight?(selector)
    page.evaluate_script(<<~JS, selector)
      ((selector) => {
        const message = document.querySelector(selector)
        const list = message.closest("[data-chat-target='messages']")
        const a = message.getBoundingClientRect(), b = list.getBoundingClientRect()
        return a.top >= b.top - 1 && a.bottom <= b.bottom + 1
      })(arguments[0])
    JS
  end
end

# frozen_string_literal: true

require "application_system_test_case"

# A chat as a tile in the workspace's own page (workspace_controller.js#inThisPage).
# What every such tile does is in workspace_in_page_test.rb; this is what a chat has
# of its own: what is sent to it arrives in it, and in no other chat on the page.
class WorkspaceInPageChatTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  CHAT = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @user = users(:one)
    @colleague = users(:two)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.assign_attributes(name: "Chat", icon: "message-circle", enabled: true) }
    @tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    @tool.collaborators.create!(user: @colleague, role: "collaborator")
    @other = Tool.create!(name: "Side Chat", tool_type: chat_type, owner: @user)
    @tool.chat.messages.create!(user: @colleague, body: "Standup at 2?")

    sign_in_as @user
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path("in-page": "todos,boards,chat", open: tool_path(@tool))
    wait_for_stimulus "workspace"
    assert_selector "#{CHAT} .tile-page h1", text: @tool.name
    wait_for_stimulus "chat"
    # (the line about tiles a first visit gets lies over the message box)
    within(".workspace-hint") { click_on "Got it" }
  end

  teardown do
    page.execute_script("try { localStorage.removeItem('dobase:workspace:in-page') } catch (error) {}")
  end

  test "the chat is part of the workspace's page, and opening it reads it" do
    within(CHAT) { assert_text "Standup at 2?" }
    assert_equal 0, page.evaluate_script("window.frames.length")
    assert_db_change -> { @tool.chat.unread_count_for(@user).zero? }
  end

  test "a message is sent with Enter, and the box is ready for the next one" do
    editable = find("#{CHAT} form rhino-editor .ProseMirror")
    editable.click
    editable.send_keys("On my way", :enter)

    assert_selector "#{CHAT} .chat-messages", text: "On my way"
    assert_equal "On my way", @tool.chat.messages.last.body.to_plain_text
    assert_current_path workspace_path
    assert_selector "#{CHAT} form rhino-editor .ProseMirror:focus"
    assert_equal "", find("#{CHAT} form rhino-editor .ProseMirror").text
  end

  test "someone else's message arrives while you look" do
    assert_selector "#{CHAT} turbo-cable-stream-source[connected]", visible: :all
    @tool.chat.messages.create!(user: @colleague, body: "Bring the samples")

    assert_selector "#{CHAT} .chat-messages", text: "Bring the samples"
  end

  test "with two chats on the page, a message arrives in its own chat only" do
    @other.chat.messages.create!(user: @user, body: "Nothing here yet")
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(@other))
    assert_selector CHAT, count: 2
    side = "##{@other.chat.part_id(:messages)}"
    team = "##{@tool.chat.part_id(:messages)}"
    assert_selector side, text: "Nothing here yet"
    # Both chats are listening before anything is said (a message sent before a
    # page listens is not sent again)
    assert_selector "#{CHAT} turbo-cable-stream-source[connected]", count: 2, visible: :all

    @tool.chat.messages.create!(user: @colleague, body: "For the team")
    @other.chat.messages.create!(user: @user, body: "For the side")

    assert_selector team, text: "For the team"
    assert_selector side, text: "For the side"
    assert_no_selector side, text: "For the team"
    assert_no_selector team, text: "For the side"
  end

  test "the slash goes to the message box, and Escape comes back out" do
    find(CHAT).click
    find("#{CHAT} .tile-page").send_keys(:escape)
    find("#{CHAT} .tile-page").send_keys("/")

    assert_selector "#{CHAT} form rhino-editor .ProseMirror:focus"
  end

  test "an emoji is put on a message from the tile" do
    message = @tool.chat.messages.last
    within("#{CHAT} ##{ActionView::RecordIdentifier.dom_id(message)}") do
      find("[title='Add a reaction']", visible: :all).execute_script("this.click()")
      find("[aria-label='React with 👍']").click
      assert_selector ".chat-reaction[aria-pressed='true']", text: /👍\s+1/
    end
    assert_equal 1, message.reactions.count
  end

  test "your own message is rewritten in place" do
    mine = @tool.chat.messages.create!(user: @user, body: "See you at 3")
    assert_selector "#{CHAT} .chat-messages", text: "See you at 3"

    within("#{CHAT} ##{ActionView::RecordIdentifier.dom_id(mine)}") do
      find("[title='Edit']", visible: :all).execute_script("this.click()")
      editable = find("rhino-editor .ProseMirror")
      editable.click
      editable.send_keys([ :end ], " sharp", :enter)
    end

    assert_selector "#{CHAT} .chat-messages", text: "See you at 3 sharp"
    assert_selector "#{CHAT} .tile-page h1", text: @tool.name
    assert_current_path workspace_path
  end

  test "the arrows go through the messages and never out of the chat" do
    3.times { |number| @tool.chat.messages.create!(user: @colleague, body: "Line #{number}") }
    assert_selector "#{CHAT} .chat-messages", text: "Line 2"
    find("#{CHAT} .tile-page h1").click

    %i[arrow_up arrow_up arrow_up arrow_down arrow_left arrow_right arrow_up].each do |arrow|
      page.send_keys(arrow)
      inside = page.evaluate_script("Boolean(document.activeElement.closest('turbo-frame.tile-frame'))")
      assert inside, "#{arrow} took the keyboard out of the chat"
    end
  end
end

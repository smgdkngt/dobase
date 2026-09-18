# frozen_string_literal: true

require "test_helper"

class Tools::Chats::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.name = "Chat"; type.icon = "message-circle"; type.enabled = true }
    @tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    @chat = @tool.chat
    sign_in_as @user
  end

  test "a failed send shows an error, and the next successful send clears it" do
    post tool_chat_messages_path(@tool), params: { message: { body: "" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "can&#39;t be blank"

    post tool_chat_messages_path(@tool), params: { message: { body: "Hello" } }
    assert_response :success
    # A bare 200 with no body (the old behavior) would leave the previous
    # error showing forever — the response must carry a stream that actually
    # updates (clears) the error slot's contents. It must be "update", not
    # "replace": shared/error_flash renders no element with this id itself,
    # so a replace would remove the slot from the page entirely, leaving
    # nothing for a later failed send to target.
    assert_select "turbo-stream[action=update][target=chat-form-errors]"
    assert_not_includes response.body, "can&#39;t be blank"
  end

  test "the error slot survives a clear so a later failed send can still show its error" do
    post tool_chat_messages_path(@tool), params: { message: { body: "" } }
    assert_response :unprocessable_entity

    post tool_chat_messages_path(@tool), params: { message: { body: "Hello" } }
    assert_response :success

    post tool_chat_messages_path(@tool), params: { message: { body: "" } }
    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=update][target=chat-form-errors]"
    assert_includes response.body, "can&#39;t be blank"
  end

  test "the chat page offers the older messages it didn't render" do
    messages = add_messages(Chats::Chat::MESSAGES_PER_PAGE + 5)

    get tool_chat_path(@tool)

    assert_response :success
    assert_select "#chat_older_messages a[href=?]", tool_chat_messages_path(@tool, before: messages[5].id)
    assert_no_match(/Message 0\b/, response.body)
    assert_match(/Message 5\b/, response.body)
  end

  test "a chat that fits on the page offers nothing older" do
    add_messages(3)

    get tool_chat_path(@tool)

    assert_response :success
    assert_select "#chat_older_messages a", false
  end

  test "older messages are prepended above the ones already on the page" do
    messages = add_messages(Chats::Chat::MESSAGES_PER_PAGE + 5)

    get tool_chat_messages_path(@tool, before: messages[5].id), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "turbo-stream[action=prepend][target=chat_messages]"
    assert_select "turbo-stream[action=replace][target=chat_older_messages]"
    assert_match(/Message 0\b/, response.body)
    assert_no_match(/Message 5\b/, response.body)
  end

  test "the day's separator moves up with the messages that now open it" do
    messages = add_messages(4)

    get tool_chat_messages_path(@tool, before: messages[2].id), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # Both pages hold messages from the same day, so the separator the page
    # already shows has to go — the prepended page brings its own, above the
    # older messages where it belongs.
    assert_select "turbo-stream[action=remove][target=?]", "chat_date_#{messages[1].created_at.to_date}"
  end

  test "the author is offered a form to edit their own message" do
    message = @chat.messages.create!(user: @user, body: "<p>Typo</p>")

    get edit_tool_chat_message_path(@tool, message)

    assert_response :success
    assert_select "turbo-frame#body_chats_message_#{message.id} form[action=?]", tool_chat_message_path(@tool, message)
  end

  test "someone else's message can't be edited from the page" do
    other = users(:two)
    @tool.collaborators.create!(user: other, role: "collaborator")
    message = @chat.messages.create!(user: other, body: "<p>Theirs</p>")

    get edit_tool_chat_message_path(@tool, message)

    assert_response :forbidden
  end

  test "an edit puts the rewritten message back on the page" do
    message = @chat.messages.create!(user: @user, body: "<p>Typo</p>")

    patch tool_chat_message_path(@tool, message), params: { message: { body: "<p>Fixed</p>" } }

    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", "chats_message_#{message.id}"
    assert_includes response.body, "Fixed"
    assert_predicate message.reload.edited_at, :present?
  end

  test "an edited message says so" do
    @chat.messages.create!(user: @user, body: "<p>Rewritten</p>", edited_at: Time.current)

    get tool_chat_path(@tool)

    assert_response :success
    assert_select "[data-message-edited]", text: "edited"
  end

  test "a message that was never edited says nothing" do
    @chat.messages.create!(user: @user, body: "<p>As sent</p>")

    get tool_chat_path(@tool)

    assert_response :success
    assert_select "[data-message-edited]", false
  end

  private

  def add_messages(count)
    count.times.map { |index| @chat.messages.create!(user: @user, body: "<p>Message #{index}</p>") }
  end
end

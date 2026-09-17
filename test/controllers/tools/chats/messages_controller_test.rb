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
end

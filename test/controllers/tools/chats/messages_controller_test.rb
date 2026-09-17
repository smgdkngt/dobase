# frozen_string_literal: true

require "test_helper"

class Tools::Chats::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tool = Tool.create!(name: "Team Chat", tool_type: tool_types(:board), owner: @user)
    # Reuse the board tool type's collaborator record; chat itself is
    # auto-created by the Tool creation callback for chat-type tools, so
    # build the chat/tool association directly for this generic tool.
    @chat = Chats::Chat.create!(tool: @tool)
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
    # replaces (clears) the error slot.
    assert_includes response.body, 'target="chat-form-errors"'
    assert_not_includes response.body, "can&#39;t be blank"
  end
end

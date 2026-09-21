# frozen_string_literal: true

require "test_helper"

class NotificationsReadOnOpenTest < ActionDispatch::IntegrationTest
  setup do
    @reader = users(:one)
    @writer = users(:two)
    chat_type = ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle")
    @chat_tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @reader)
    @chat_tool.collaborators.create!(user: @writer, role: "collaborator")
    sign_in_as @reader
  end

  test "opening the chat reads its message notifications" do
    2.times { |i| @chat_tool.chat.messages.create!(user: @writer, body: "<p>Hi #{i}</p>") }
    assert_equal 2, @reader.notifications.unread.count

    get tool_chat_path(@chat_tool)

    assert_response :success
    assert_equal 0, @reader.notifications.unread.count
  end

  test "reading the chat through the API leaves them unread" do
    @chat_tool.chat.messages.create!(user: @writer, body: "<p>Hi</p>")

    get tool_chat_path(@chat_tool), headers: api_headers(@reader, permission: "read")

    assert_equal 1, @reader.notifications.unread.count
  end
end

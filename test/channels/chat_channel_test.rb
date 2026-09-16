# frozen_string_literal: true

require "test_helper"

class ChatChannelTest < ActionCable::Channel::TestCase
  setup do
    chat_type = ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle")
    @chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: users(:one)).chat
  end

  test "a collaborator subscribes and says hello, so others answer" do
    stub_connection current_user: users(:one)

    assert_broadcast_on(ChatChannel.broadcasting_for(@chat), presence(users(:one), hello: true)) do
      subscribe chat_id: @chat.id
    end

    assert subscription.confirmed?
    assert_has_stream_for @chat
  end

  test "answering a hello announces presence without asking again" do
    stub_connection current_user: users(:one)
    subscribe chat_id: @chat.id

    assert_broadcast_on(ChatChannel.broadcasting_for(@chat), presence(users(:one), hello: false)) do
      perform :announce_presence
    end
  end

  test "someone without access is rejected and never shows up in the chat" do
    stub_connection current_user: users(:two)

    assert_no_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      subscribe chat_id: @chat.id
    end

    assert subscription.rejected?
  end

  test "an unknown chat is rejected" do
    stub_connection current_user: users(:one)

    subscribe chat_id: 0

    assert subscription.rejected?
  end

  private

  def presence(user, hello:)
    { type: "presence", user_id: user.id, user_name: user.name, status: "online", hello: hello }
  end
end

# frozen_string_literal: true

require "test_helper"

class ChatChannelTest < ActionCable::Channel::TestCase
  setup do
    chat_type = ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle")
    @chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: users(:one)).chat
    ChatPresence.reset!
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

  test "closing one of two tabs leaves the user online" do
    stub_connection current_user: users(:one)
    subscribe chat_id: @chat.id
    second_tab = open_another_tab

    assert_no_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      second_tab.unsubscribe_from_channel
    end
  end

  test "the last tab going marks the user offline" do
    stub_connection current_user: users(:one)
    subscribe chat_id: @chat.id
    second_tab = open_another_tab
    second_tab.unsubscribe_from_channel

    assert_broadcast_on(ChatChannel.broadcasting_for(@chat), presence(users(:one), hello: false).merge(status: "offline")) do
      subscription.unsubscribe_from_channel
    end
  end

  test "an unknown chat is rejected" do
    stub_connection current_user: users(:one)

    subscribe chat_id: 0

    assert subscription.rejected?
  end

  private

  # A second subscription for the same user on the same connection: another
  # browser tab, which the test case's own `subscribe` can't model.
  def open_another_tab
    ChatChannel.new(subscription.connection, "second-tab", { "chat_id" => @chat.id }).tap(&:subscribe_to_channel)
  end

  def presence(user, hello:)
    { type: "presence", user_id: user.id, user_name: user.name, status: "online", hello: hello }
  end
end

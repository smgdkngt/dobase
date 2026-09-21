# frozen_string_literal: true

require "test_helper"

class NotificationFeedTest < ActiveSupport::TestCase
  setup do
    @tool = tools(:shared_board)
    @reader = users(:one)
    @writer = users(:two)
    chat_type = ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle")
    @chat_tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @reader)
    @chat_tool.collaborators.create!(user: @writer, role: "collaborator")
  end

  test "a busy chat is one line, saying who and how many" do
    3.times { |i| deliver_chat_message("Message #{i}") }

    entries = feed.entries

    assert_equal 1, entries.size
    entry = entries.first
    assert entry.grouped?
    assert_equal 3, entry.ids.size
    assert_equal "User sent 3 messages in Team Chat", entry.message
    assert_equal @writer, entry.actor
    assert_equal "Message 2", entry.excerpt
  end

  test "a single message is its own line, quoting what was said" do
    deliver_chat_message("Can you look at the label?")

    entry = feed.entries.sole

    assert_not entry.grouped?
    assert_equal "Can you look at the label?", entry.excerpt
    assert_equal @writer, entry.actor
  end

  test "read chat messages are no longer folded together" do
    2.times { |i| deliver_chat_message("Message #{i}") }
    @reader.notifications.each(&:mark_as_read!)

    assert_equal 2, feed.entries.size
  end

  test "a notification with nobody behind it still reads" do
    MentionNotifier.with(mentioner: nil, tool: @tool, context: "Shared Notes", url: "/somewhere").deliver(@reader)

    entry = feed.entries.sole

    assert_nil entry.actor
    assert_equal "Someone mentioned you in Shared Notes", entry.message
  end

  private

  def deliver_chat_message(text)
    # A chat message tells the others itself
    @chat_tool.chat.messages.create!(user: @writer, body: "<p>#{text}</p>")
  end

  def feed
    NotificationFeed.new(@reader.notifications.includes(:event).newest_first)
  end
end

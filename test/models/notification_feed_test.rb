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

  test "a notification about a deleted chat message still says who and where" do
    deliver_chat_message("Never mind").destroy!

    entry = feed.entries.sole

    assert_equal "#{@writer.name} sent a message in Team Chat", entry.message
    assert_equal "/tools/#{@chat_tool.id}/chat", entry.url
    assert_equal @chat_tool, entry.tool
    assert_equal @writer, entry.actor
    assert_nil entry.excerpt
  end

  test "deleted messages in different chats aren't folded into one line" do
    other_chat = Tool.create!(name: "Other Chat", tool_type: @chat_tool.tool_type, owner: @reader)
    other_chat.collaborators.create!(user: @writer, role: "collaborator")

    deliver_chat_message("Never mind").destroy!
    other_chat.chat.messages.create!(user: @writer, body: "<p>Wrong chat</p>").destroy!

    entries = feed.entries

    assert_equal [ other_chat, @chat_tool ], entries.map(&:tool)
    assert_equal [ "/tools/#{other_chat.id}/chat", "/tools/#{@chat_tool.id}/chat" ], entries.map(&:url)
    assert entries.none?(&:grouped?)
  end

  test "a notification about a deleted comment still leads to its card" do
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Shared card", position: 0)
    Boards::Comment.create!(card: card, user: @writer, body: "<p>Looks good</p>").destroy!

    entry = feed.entries.sole

    assert_equal "#{@writer.name} commented on Shared card", entry.message
    assert_equal "/tools/#{@tool.id}/board?card=#{card.id}", entry.url
    assert_equal @tool, entry.tool
    assert_nil entry.excerpt
  end

  test "a notification from someone who deleted their account still leads to the chat" do
    leaver = User.create!(first_name: "Gone", last_name: "Soon", email_address: "gone-soon@example.com", password: "password123")
    @chat_tool.collaborators.create!(user: leaver, role: "collaborator")
    @chat_tool.chat.messages.create!(user: leaver, body: "<p>Bye all</p>")
    leaver.destroy!

    entry = feed.entries.sole

    assert_equal "Someone sent a message in Team Chat", entry.message
    assert_equal "/tools/#{@chat_tool.id}/chat", entry.url
    assert_equal "Bye all", entry.excerpt
  end

  test "chat messages that no longer say which chat stay a line each" do
    2.times { ChatMessageNotifier.with(message: nil, sender: @writer, tool: nil).deliver(@reader) }

    entries = feed.entries

    assert_equal 2, entries.size
    assert entries.none?(&:grouped?)
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

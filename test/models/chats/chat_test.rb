# frozen_string_literal: true

require "test_helper"

module Chats
  class ChatTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @other = users(:two)
      @tool = tools(:shared_board)
      @chat = Chats::Chat.create!(tool: @tool)
    end

    test "a message you sent yourself is never unread for you" do
      @chat.messages.create!(user: @user, body: "<p>Mine</p>")

      assert_equal 0, @chat.unread_count_for(@user)
      assert_equal 1, @chat.unread_count_for(@other)
    end

    test "reading a chat remembers the last message, and reading it again moves on" do
      first = @chat.messages.create!(user: @other, body: "<p>One</p>")
      receipt = @chat.mark_as_read_for!(@user)

      assert_equal first, receipt.last_read_message
      assert_equal @user, receipt.user

      second = @chat.messages.create!(user: @other, body: "<p>Two</p>")
      again = @chat.mark_as_read_for!(@user)

      assert_equal receipt.id, again.id
      assert_equal second, again.last_read_message
      assert_equal 1, @chat.read_receipts.where(user: @user).count
    end

    # Two tabs opening a chat for the first time both find no receipt yet
    test "a first read that loses the race to another first read doesn't fail" do
      message = @chat.messages.create!(user: @other, body: "<p>Hello</p>")
      raced = false
      # Right after this request has looked for its receipt and found none
      another_request_reads_first = lambda do |*, payload|
        next if raced || !payload[:sql].start_with?(%(SELECT "chat_read_receipts".*))

        raced = true
        Chats::ReadReceipt.insert_all([ { chat_id: @chat.id, user_id: @user.id, last_read_at: 1.minute.ago } ])
      end

      receipt = ActiveSupport::Notifications.subscribed(another_request_reads_first, "sql.active_record") do
        @chat.mark_as_read_for!(@user)
      end

      assert_equal message, receipt.last_read_message
      assert_operator receipt.last_read_at, :>, 10.seconds.ago
      assert_equal 1, @chat.read_receipts.where(user: @user).count
      assert_equal 0, @chat.unread_count_for(@user)
    end

    test "only other people's messages since the last read count as unread" do
      @chat.mark_as_read_for!(@user)
      @chat.messages.create!(user: @user, body: "<p>Mine</p>")
      @chat.messages.create!(user: @other, body: "<p>Theirs</p>")

      assert_equal 1, @chat.unread_count_for(@user)
    end
  end
end

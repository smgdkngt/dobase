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

    test "only other people's messages since the last read count as unread" do
      @chat.mark_as_read_for!(@user)
      @chat.messages.create!(user: @user, body: "<p>Mine</p>")
      @chat.messages.create!(user: @other, body: "<p>Theirs</p>")

      assert_equal 1, @chat.unread_count_for(@user)
    end
  end
end

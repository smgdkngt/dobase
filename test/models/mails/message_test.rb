# frozen_string_literal: true

require "test_helper"

module Mails
  class MessageTest < ActiveSupport::TestCase
    setup do
      @message = mails_messages(:inbox_unread)
    end

    test "remembers when a message went to the trash, and forgets it on restore" do
      freeze_time do
        @message.update!(trashed: true)
        assert_equal Time.current, @message.trashed_at
      end

      travel 1.day do
        @message.update!(read: true)
        assert_equal 1.day.ago, @message.reload.trashed_at
      end

      @message.update!(trashed: false)
      assert_nil @message.reload.trashed_at
    end
  end
end

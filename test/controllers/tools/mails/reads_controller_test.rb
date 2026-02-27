# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class ReadsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
      end

      test "create marks message as read" do
        msg = mails_messages(:inbox_unread)
        assert_not msg.read
        post tool_mail_read_path(@tool, msg)
        assert msg.reload.read
      end

      test "destroy marks message as unread" do
        msg = mails_messages(:inbox_read)
        assert msg.read
        delete tool_mail_read_path(@tool, msg)
        assert_not msg.reload.read
      end
    end
  end
end

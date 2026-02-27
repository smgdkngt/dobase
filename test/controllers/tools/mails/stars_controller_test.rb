# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class StarsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
      end

      test "create stars a message" do
        msg = mails_messages(:inbox_read)
        assert_not msg.starred
        post tool_mail_star_path(@tool, msg)
        assert msg.reload.starred
      end

      test "destroy unstars a message" do
        msg = mails_messages(:starred_message)
        assert msg.starred
        delete tool_mail_star_path(@tool, msg)
        assert_not msg.reload.starred
      end
    end
  end
end

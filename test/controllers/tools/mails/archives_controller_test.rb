# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class ArchivesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
      end

      test "create archives a message" do
        msg = mails_messages(:inbox_read)
        post tool_mail_archive_path(@tool, msg)
        assert msg.reload.archived
      end

      test "destroy unarchives a message" do
        msg = mails_messages(:archived_message)
        delete tool_mail_archive_path(@tool, msg)
        assert_not msg.reload.archived
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class TrashesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
      end

      test "create trashes a message" do
        msg = mails_messages(:inbox_read)
        post tool_mail_trash_path(@tool, msg)
        assert msg.reload.trashed
      end

      test "destroy restores a message from trash" do
        msg = mails_messages(:trashed_message)
        delete tool_mail_trash_path(@tool, msg)
        assert_not msg.reload.trashed
      end

      test "destroy_all empties trash" do
        assert ::Mails::Message.where(mail_account_id: mails_accounts(:primary).id).trashed.any?
        delete tool_empty_trash_path(@tool)
        assert ::Mails::Message.where(mail_account_id: mails_accounts(:primary).id).trashed.none?
      end
    end
  end
end

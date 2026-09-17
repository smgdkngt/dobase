# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class MovesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
      end

      test "create moves message to target folder" do
        msg = mails_messages(:inbox_read)
        post tool_mail_move_path(@tool, msg), params: { folder: "Receipts" }
        msg.reload
        assert_equal "Receipts", msg.folder
        assert_not msg.archived
        assert_not msg.trashed
      end

      test "create moves the whole conversation in the current folder" do
        older, newer = create_mail_thread
        assert_enqueued_jobs 2, only: ImapSyncJob do
          post tool_mail_move_path(@tool, newer), params: { folder: "Receipts", current_folder: "inbox" }
        end
        assert_equal "Receipts", older.reload.folder
        assert_equal "INBOX", mails_messages(:inbox_read).reload.folder
      end

      test "create with blank folder shows error" do
        msg = mails_messages(:inbox_read)
        post tool_mail_move_path(@tool, msg), params: { folder: "" }
        assert_redirected_to tool_mails_path(@tool)
      end
    end
  end
end

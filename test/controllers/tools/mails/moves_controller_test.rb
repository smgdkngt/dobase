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

      test "mail moves to a folder inside the inbox by its own name, and says so by that name" do
        @tool.mail_account.update!(folder_prefix: "INBOX.", synced_folders: %w[INBOX Sent INBOX.Receipts].to_json)
        msg = mails_messages(:inbox_read)
        msg.update!(uid: 102)

        assert_enqueued_with(job: ImapSyncJob, args: [ msg.mail_account_id, "move_to_folder", 102, "INBOX", "INBOX.Receipts" ]) do
          post tool_mail_move_path(@tool, msg), params: { folder: "Receipts" }
        end
        assert_equal "INBOX.Receipts", msg.reload.folder
        assert_equal "Moved to Receipts.", flash[:notice]
      end

      test "mail moves to any folder the server has, whatever is in its name" do
        @tool.mail_account.update!(synced_folders: [ "INBOX", "Sent", "Facturen &- bonnen", "Work (old)", "B&APw-ro", "Klanten/Caf&AOk-" ].to_json)
        msg = mails_messages(:inbox_read)

        [ [ "Facturen &- bonnen", "Facturen & bonnen" ], [ "Work (old)", "Work (old)" ], [ "B&APw-ro", "Büro" ], [ "Klanten/Caf&AOk-", "Klanten/Café" ] ].each do |folder, name|
          msg.update!(folder: "INBOX", uid: 102)

          assert_enqueued_with(job: ImapSyncJob, args: [ msg.mail_account_id, "move_to_folder", 102, "INBOX", folder ]) do
            post tool_mail_move_path(@tool, msg), params: { folder: folder }
          end

          assert_equal folder, msg.reload.folder
          assert_equal "Moved to #{name}.", flash[:notice]
        end
      end

      test "mail doesn't move to a folder the server doesn't have" do
        msg = mails_messages(:inbox_read)

        assert_no_enqueued_jobs only: ImapSyncJob do
          [ "Projects", "Receipts*", "", "Trash", "Drafts" ].each do |folder|
            post tool_mail_move_path(@tool, msg), params: { folder: folder }

            assert_equal "Invalid folder name.", flash[:alert], folder
          end
        end
        assert_equal "INBOX", msg.reload.folder
      end

      test "the inbox and sent mail are always folders to move to" do
        @tool.mail_account.update!(synced_folders: nil)
        msg = mails_messages(:inbox_read)

        post tool_mail_move_path(@tool, msg), params: { folder: "Sent" }
        assert_equal "Sent", msg.reload.folder

        post tool_mail_move_path(@tool, msg), params: { folder: "INBOX", current_folder: "sent" }
        assert_equal "INBOX", msg.reload.folder
      end

      test "create with blank folder shows error" do
        msg = mails_messages(:inbox_read)
        post tool_mail_move_path(@tool, msg), params: { folder: "" }
        assert_redirected_to tool_mails_path(@tool)
      end
    end
  end
end

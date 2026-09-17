# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class BulkActionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
        @msg1 = mails_messages(:inbox_unread)
        @msg2 = mails_messages(:inbox_read)
      end

      test "bulk archive" do
        post tool_bulk_path(@tool), params: { message_ids: [ @msg1.id, @msg2.id ], action_type: "archive" }
        assert @msg1.reload.archived
        assert @msg2.reload.archived
      end

      test "bulk trash" do
        post tool_bulk_path(@tool), params: { message_ids: [ @msg1.id, @msg2.id ], action_type: "trash" }
        assert @msg1.reload.trashed
        assert @msg2.reload.trashed
        assert_not_nil @msg1.trashed_at
      end

      test "bulk restore takes messages out of trash" do
        trashed = mails_messages(:trashed_message)
        trashed.update_column(:trashed_at, 1.day.ago)

        assert_no_enqueued_jobs do
          post tool_bulk_path(@tool), params: { message_ids: [ trashed.id, @msg1.id ], action_type: "restore" }
        end

        assert_not trashed.reload.trashed
        assert_nil trashed.trashed_at
        assert_equal "1 email(s) restored.", flash[:notice]
      end

      test "bulk archive, trash, restore and delete act on whole conversations" do
        older, newer = create_mail_thread

        post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "archive", folder: "inbox" }
        assert older.reload.archived?
        assert_equal "2 email(s) archived.", flash[:notice]

        [ older, newer ].each { |message| message.update!(archived: false) }
        post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "trash", folder: "inbox" }
        assert older.reload.trashed?
        assert_equal "2 email(s) moved to trash.", flash[:notice]

        post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "restore", folder: "trash" }
        assert_not older.reload.trashed?

        [ older, newer ].each { |message| message.update!(trashed: true) }
        assert_difference "::Mails::Message.count", -2 do
          post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "delete", folder: "trash" }
        end
      end

      test "bulk mark read, mark unread and move act on whole conversations in the folder" do
        older, newer = create_mail_thread
        elsewhere = mails_accounts(:primary).messages.create!(message_id: "<lunch-203@example.com>", folder: "Receipts", uid: 203,
          subject: "Lunch?", from_address: "ann@example.com", to_addresses: "[]", sent_at: 3.hours.ago, thread_id: "thread-lunch")

        assert_enqueued_jobs 2, only: ImapSyncJob do
          post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "mark_read", folder: "inbox" }
        end
        assert older.reload.read?
        assert_not elsewhere.reload.read?
        assert_equal "2 email(s) marked as read.", flash[:notice]

        post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "mark_unread", folder: "inbox" }
        assert_not older.reload.read?
        assert_equal "2 email(s) marked as unread.", flash[:notice]

        assert_enqueued_jobs 2, only: ImapSyncJob do
          post tool_bulk_path(@tool), params: { message_ids: [ newer.id ], action_type: "move_to_folder", target_folder: "Projects", folder: "inbox" }
        end
        assert_equal "Projects", older.reload.folder
        assert_equal "Receipts", elsewhere.reload.folder
        assert_equal "2 email(s) moved to Projects.", flash[:notice]
      end

      test "bulk mark_read" do
        post tool_bulk_path(@tool), params: { message_ids: [ @msg1.id ], action_type: "mark_read" }
        assert @msg1.reload.read
      end

      test "bulk mark_unread" do
        post tool_bulk_path(@tool), params: { message_ids: [ @msg2.id ], action_type: "mark_unread" }
        assert_not @msg2.reload.read
      end

      test "bulk move_to_folder" do
        post tool_bulk_path(@tool), params: { message_ids: [ @msg1.id, @msg2.id ], action_type: "move_to_folder", target_folder: "Receipts" }
        assert_equal "Receipts", @msg1.reload.folder
        assert_equal "Receipts", @msg2.reload.folder
      end

      test "bulk delete permanently removes trashed messages" do
        trashed = mails_messages(:trashed_message)
        assert_difference "::Mails::Message.count", -1 do
          post tool_bulk_path(@tool), params: { message_ids: [ trashed.id ], action_type: "delete" }
        end
      end

      test "empty message_ids does nothing" do
        post tool_bulk_path(@tool), params: { message_ids: [], action_type: "archive" }
        assert_redirected_to tool_mails_path(@tool)
      end

      test "acts on up to the maximum number of messages" do
        ids = [ @msg1.id, *unknown_ids(BulkActionsController::MAX_MESSAGES - 1) ]

        assert_enqueued_jobs 1, only: ImapSyncJob do
          post tool_bulk_path(@tool), params: { message_ids: ids, action_type: "archive" }
        end

        assert @msg1.reload.archived
      end

      test "refuses more than the maximum number of messages" do
        ids = [ @msg1.id, *unknown_ids(BulkActionsController::MAX_MESSAGES) ]

        assert_no_enqueued_jobs do
          post tool_bulk_path(@tool), params: { message_ids: ids, action_type: "archive" }
        end

        assert_redirected_to tool_mails_path(@tool)
        assert_equal "Select up to #{BulkActionsController::MAX_MESSAGES} emails at a time.", flash[:alert]
        assert_not @msg1.reload.archived
      end

      private

      def unknown_ids(count)
        first = ::Mails::Message.maximum(:id) + 1
        (first...first + count).to_a
      end
    end
  end
end

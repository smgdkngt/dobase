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
      end

      test "bulk restore takes messages out of trash" do
        trashed = mails_messages(:trashed_message)

        assert_no_enqueued_jobs do
          post tool_bulk_path(@tool), params: { message_ids: [ trashed.id, @msg1.id ], action_type: "restore" }
        end

        assert_not trashed.reload.trashed
        assert_equal "1 email(s) restored.", flash[:notice]
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

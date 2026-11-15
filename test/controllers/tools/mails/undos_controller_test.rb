# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class UndosControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
        @account = @tool.mail_account
        @message = mails_messages(:inbox_unread)
      end

      test "archived mail has an Undo on its notice, which puts it back in the inbox and opens it there" do
        post tool_mail_archive_path(@tool, @message, folder: "inbox")
        assert_equal tool_undo_path(@tool), flash[:undo]["url"]
        follow_redirect!
        assert_select ".flash", text: /Email archived\./ do
          assert_select "form[action='#{tool_undo_path(@tool)}'][data-flash-undo] button[data-hotkey=z]", text: "Undo"
        end

        post tool_undo_path(@tool), params: { undo: undo_token }

        assert_redirected_to tool_mail_path(@tool, @message, folder: "inbox")
        assert_equal "Undone.", flash[:notice]
        assert_not @message.reload.archived?
      end

      test "trashed mail comes back from the trash" do
        delete tool_mail_path(@tool, @message, folder: "inbox")
        assert @message.reload.trashed?

        post tool_undo_path(@tool), params: { undo: undo_token }
        assert_not @message.reload.trashed?
      end

      test "mail moved to a folder, and to junk, goes back" do
        post tool_mail_move_path(@tool, @message), params: { folder: "Receipts", current_folder: "inbox" }
        post tool_undo_path(@tool), params: { undo: undo_token }
        assert_equal "INBOX", @message.reload.folder

        @account.update!(synced_folders: %w[INBOX Sent Junk].to_json)
        post tool_mail_junk_path(@tool, @message, folder: "inbox")
        assert @message.reload.junk?
        post tool_undo_path(@tool), params: { undo: undo_token }
        assert_equal "INBOX", @message.reload.folder
      end

      test "mail archived several at a time comes back together, to its folder's list" do
        messages = [ @message, mails_messages(:inbox_read) ]
        post tool_bulk_path(@tool), params: { action_type: "archive", message_ids: messages.map(&:id), folder: "inbox" }
        assert messages.all? { _1.reload.archived? }

        post tool_undo_path(@tool), params: { undo: undo_token }

        assert_redirected_to tool_mails_path(@tool, folder: "inbox")
        assert messages.none? { _1.reload.archived? }
      end

      test "a changed token undoes nothing" do
        post tool_mail_archive_path(@tool, @message, folder: "inbox")

        post tool_undo_path(@tool), params: { undo: undo_token.succ }

        assert_equal "That can't be undone any more.", flash[:alert]
        assert @message.reload.archived?
      end

      test "an old token undoes nothing" do
        post tool_mail_archive_path(@tool, @message, folder: "inbox")
        token = undo_token

        travel 6.minutes do
          post tool_undo_path(@tool), params: { undo: token }
        end

        assert @message.reload.archived?
      end

      test "a token taken to another mail tool undoes nothing there, nor here" do
        Collaborator.create!(tool: tools(:other_mail), user: users(:one), role: "collaborator")
        post tool_mail_archive_path(@tool, @message, folder: "inbox")

        post tool_undo_path(tools(:other_mail)), params: { undo: undo_token }

        assert_equal "That can't be undone any more.", flash[:alert]
        assert @message.reload.archived?
      end

      test "someone else's token undoes nothing, and without the tool nothing is reached" do
        post tool_mail_archive_path(@tool, @message, folder: "inbox")
        token = undo_token

        sign_in_as users(:two)
        post tool_undo_path(@tool), params: { undo: token }

        assert_redirected_to root_path
        assert @message.reload.archived?
      end

      test "the API archives without an Undo" do
        post tool_mail_archive_path(@tool, @message, format: :json), headers: api_headers(users(:one))

        assert_response :success
        assert_nil flash[:undo]
      end

      private

      def undo_token
        flash[:undo]&.dig("params", "undo") || raise("no Undo offered")
      end
    end
  end
end

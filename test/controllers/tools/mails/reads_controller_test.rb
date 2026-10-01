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

      # Opening a message marks it read, so a message marked unread while it's open has to close

      test "marking the open message unread goes back to its folder, and leaves it unread" do
        msg = mails_messages(:inbox_read)

        delete tool_mail_read_path(@tool, msg, folder: "sent"), headers: { "HTTP_REFERER" => tool_mail_url(@tool, msg, folder: "sent") }
        assert_redirected_to tool_mails_path(@tool, folder: "sent")
        follow_redirect!

        assert_not msg.reload.read
        assert_equal [ [ msg.mail_account_id, "mark_as_unread", 102, "INBOX" ] ],
          enqueued_jobs.select { |job| job["job_class"] == "ImapSyncJob" }.map { |job| job["arguments"] }
      end

      test "a message that was unread when it was opened offers to mark it unread" do
        msg = mails_messages(:inbox_unread)

        get tool_mail_path(@tool, msg, folder: "inbox")

        assert_select "a[title='Mark unread (u)'][data-turbo-method=delete][href=?]", tool_mail_read_path(@tool, msg, folder: "inbox")
      end

      test "marking read stays on the page" do
        msg = mails_messages(:inbox_unread)

        post tool_mail_read_path(@tool, msg), headers: { "HTTP_REFERER" => tool_mails_url(@tool, folder: "starred") }

        assert_redirected_to tool_mails_url(@tool, folder: "starred")
      end

      test "marking read and unread tells the mail server once each" do
        msg = mails_messages(:inbox_unread)

        post tool_mail_read_path(@tool, msg)
        delete tool_mail_read_path(@tool, msg)

        assert_equal [ [ msg.mail_account_id, "mark_as_read", 101, "INBOX" ], [ msg.mail_account_id, "mark_as_unread", 101, "INBOX" ] ],
          enqueued_jobs.select { |job| job["job_class"] == "ImapSyncJob" }.map { |job| job["arguments"] }
      end
    end
  end
end

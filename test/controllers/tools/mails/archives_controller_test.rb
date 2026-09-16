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

      test "unarchiving moves the archived message back, not the one with its old UID in the archive folder" do
        @tool.mail_account.update!(archive_folder: "Archive")
        msg = mails_messages(:archived_message)
        # Archived, the message has UID 12. Its old UID in the inbox, 106, is another message's in the archive folder.
        server = FakeImapServer.new(folders: [ "INBOX", "Archive" ], message_ids: { [ "Archive", msg.message_id ] => [ 12 ] })

        connect_to_imap(server) do
          perform_enqueued_jobs { delete tool_mail_archive_path(@tool, msg) }
        end

        assert_equal [ [ [ 12 ], "INBOX" ] ], server.copied
        assert_equal [ [ [ 12 ], "+FLAGS", [ :Deleted ] ] ], server.stored
        msg.reload
        assert_not msg.archived?
        assert_nil msg.uid, "the next inbox sync fills in the new UID"
      end

      test "unarchiving without an archive folder marks the message unread on the server" do
        msg = mails_messages(:archived_message)

        delete tool_mail_archive_path(@tool, msg)

        assert_enqueued_with job: ImapSyncJob, args: [ msg.mail_account_id, "mark_as_unread", 106, "INBOX" ]
        assert_equal 106, msg.reload.uid
      end
    end
  end
end

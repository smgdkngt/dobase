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

      test "with a trash on the server, trashing moves mail there and restoring brings it back" do
        @tool.mail_account.update!(synced_folders: %w[INBOX Sent Trash].to_json)
        msg = mails_messages(:inbox_read)
        msg.update!(uid: 21)

        server = FakeImapServer.new(folders: [ "INBOX", [ "Deleted Messages", :Trash ] ])
        connect_to_imap(server) { perform_enqueued_jobs(only: ImapSyncJob) { post tool_mail_trash_path(@tool, msg, folder: "inbox") } }

        assert_equal [ "Trash", true ], [ msg.reload.folder, msg.trashed? ]
        assert_equal [ [ [ 21 ], "Deleted Messages" ] ], server.copied

        delete tool_mail_trash_path(@tool, msg)
        assert_equal [ "INBOX", false ], [ msg.reload.folder, msg.trashed? ]
      end

      test "destroy restores a message from trash" do
        msg = mails_messages(:trashed_message)
        delete tool_mail_trash_path(@tool, msg)
        assert_not msg.reload.trashed
      end

      test "trashing a message trashes its conversation, deleting it on the server in one go" do
        older, newer = create_mail_thread
        server = FakeImapServer.new

        connect_to_imap(server) { perform_enqueued_jobs(only: ImapSyncJob) { post tool_mail_trash_path(@tool, newer, folder: "inbox") } }

        assert [ older, newer ].all? { |message| message.reload.trashed? }
        assert_equal [ [ 201, 202 ] ], server.stored.map { |uids, _action, _flags| uids.sort }

        delete tool_mail_trash_path(@tool, newer)
        assert [ older, newer ].none? { |message| message.reload.trashed? }
      end

      test "deleting a trashed conversation for good deletes its trashed messages and nothing else" do
        older, newer = create_mail_thread
        [ older, newer ].each { |message| message.update!(trashed: true) }
        in_inbox = mails_messages(:inbox_unread)
        in_inbox.update_column(:thread_id, "thread-lunch")

        connect_to_imap(FakeImapServer.new) { delete tool_mail_path(@tool, newer, folder: "inbox") }

        assert_not ::Mails::Message.exists?(older.id)
        assert_not ::Mails::Message.exists?(newer.id)
        assert ::Mails::Message.exists?(in_inbox.id)
      end

      test "destroy_all empties trash" do
        assert ::Mails::Message.where(mail_account_id: mails_accounts(:primary).id).trashed.any?
        delete tool_empty_trash_path(@tool)
        assert ::Mails::Message.where(mail_account_id: mails_accounts(:primary).id).trashed.none?
      end
    end
  end
end

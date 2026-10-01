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

      test "archiving a message archives its conversation in the folder, and unarchiving brings it back" do
        older, newer = create_mail_thread

        post tool_mail_archive_path(@tool, newer, folder: "inbox")
        assert [ older, newer ].all? { |message| message.reload.archived? }
        assert_equal [ 201, 202 ], enqueued_jobs.select { |job| job["job_class"] == "ImapSyncJob" }.map { |job| job["arguments"][2] }.sort

        delete tool_mail_archive_path(@tool, newer)
        assert [ older, newer ].none? { |message| message.reload.archived? }
      end

      test "archiving leaves the conversation's messages in other folders alone" do
        msg = mails_messages(:inbox_read)

        post tool_mail_archive_path(@tool, msg, folder: "inbox")

        assert msg.reload.archived?
        assert_not mails_messages(:sent_message).reload.archived?, "same thread, but in Sent"
      end

      test "archiving a message in a folder takes it out of the folder and back in on unarchiving" do
        @tool.mail_account.update!(archive_folder: "Archive")
        msg = @tool.mail_account.messages.create!(message_id: "<invoice@example.com>", folder: "Receipts", uid: 7, subject: "Invoice",
          from_address: "shop@example.com", to_addresses: "[]", sent_at: 1.hour.ago)

        post tool_mail_archive_path(@tool, msg, folder: "Receipts")

        assert msg.reload.archived?
        assert_enqueued_with job: ImapSyncJob, args: [ msg.mail_account_id, "move_to_folder", 7, "Receipts", "Archive" ]
        get tool_mails_path(@tool, folder: "Receipts")
        assert_no_match "Invoice", response.body
        get tool_mails_path(@tool, folder: "archive")
        assert_match "Invoice", response.body

        delete tool_mail_archive_path(@tool, msg)

        assert_not msg.reload.archived?
        assert_enqueued_with job: ImapSyncJob, args: [ msg.mail_account_id, "move_to_folder_by_message_id", nil, "Archive", "Receipts", "<invoice@example.com>" ]
        get tool_mails_path(@tool, folder: "Receipts")
        assert_match "Invoice", response.body
      end

      test "archiving sent mail takes it out of Sent" do
        msg = mails_messages(:sent_message)

        post tool_mail_archive_path(@tool, msg, folder: "sent")

        assert msg.reload.archived?
        get tool_mails_path(@tool, folder: "sent")
        assert_no_match msg.normalized_subject, response.body
      end

      # --- The Archive view, on an account with an archive folder -----------------
      # It lists mail archived here (in the folder it was archived from, flagged archived, with
      # the UID it had there) and the mail in the server's archive folder. Once the archive
      # folder has synced, mail archived here is in the list both ways.

      test "the archive offers to unarchive the open message, other folders to archive it" do
        get tool_mail_path(@tool, mails_messages(:archived_message), folder: "archive")
        assert_select "a[title='Unarchive (e)'][data-turbo-method=delete][data-hotkey=e][href=?]", tool_mail_archive_path(@tool, mails_messages(:archived_message))
        assert_select "a[title='Archive (e)']", 0
        assert_select "#bulk-form button[title='Archive (e)']", 0

        get tool_mail_path(@tool, mails_messages(:inbox_read), folder: "inbox")
        assert_select "a[title='Archive (e)'][data-turbo-method=post]"
        assert_select "a[title='Unarchive (e)']", 0
        assert_select "#bulk-form button[title='Archive (e)']", 1
      end

      test "archiving mail that is in the archive folder leaves it alone" do
        in_archive = archive_folder_copy_of(mails_messages(:inbox_read), uid: 31)

        assert_no_enqueued_jobs only: ImapSyncJob do
          post tool_mail_archive_path(@tool, in_archive, folder: "archive")
          post tool_bulk_path(@tool), params: { message_ids: [ in_archive.id ], action_type: "archive", folder: "archive" }
        end

        assert_equal [ "Archive", 31, false ], in_archive.reload.values_at(:folder, :uid, :archived)
      end

      test "unarchiving mail another mail program archived moves it to the inbox" do
        message = mails_messages(:inbox_read)
        message.update!(folder: "Archive", uid: 31)
        @tool.mail_account.update!(archive_folder: "Archive")

        delete tool_mail_archive_path(@tool, message)

        assert_equal [ "INBOX", nil, false ], message.reload.values_at(:folder, :uid, :archived)
        assert_equal [ [ message.mail_account_id, "move_to_folder", 31, "Archive", "INBOX" ] ], imap_jobs
        get tool_mails_path(@tool, folder: "archive")
        assert_no_match message.subject, response.body
      end

      test "unarchiving mail archived here takes its copy in the archive folder along, from either of them" do
        [ :itself, :copy ].each do |opened|
          archived = @tool.mail_account.messages.create!(message_id: "<#{opened}@example.com>", folder: "Receipts", uid: 7, archived: true,
            subject: "Invoice #{opened}", from_address: "shop@example.com", to_addresses: "[]", sent_at: 1.hour.ago)
          copy = archive_folder_copy_of(archived, uid: 31)
          clear_enqueued_jobs

          delete tool_mail_archive_path(@tool, opened == :copy ? copy : archived), as: :json

          assert_response :success
          assert_equal [ archived.id, "Receipts", false ], response.parsed_body.values_at("id", "folder", "archived")
          assert_equal [ "Receipts", nil, false ], archived.reload.values_at(:folder, :uid, :archived)
          assert_not ::Mails::Message.exists?(copy.id)
          assert_equal [ [ archived.mail_account_id, "move_to_folder_by_message_id", nil, "Archive", "Receipts", "<#{opened}@example.com>" ] ], imap_jobs
        end
      end

      test "trashing archived mail from the archive moves it out of the server's archive folder" do
        account = @tool.mail_account
        account.update!(synced_folders: %w[INBOX Sent Archive Trash].to_json)
        archived = archived_in_archive_folder
        server = FakeImapServer.new(folders: [ "INBOX", "Archive", [ "Deleted Messages", :Trash ] ], message_ids: { [ "Archive", "<archived-6@example.com>" ] => [ 31 ] })

        connect_to_imap(server) { perform_enqueued_jobs(only: ImapSyncJob) { post tool_mail_trash_path(@tool, archived, folder: "archive") } }

        assert_equal [ "Trash", true, false, nil ], archived.reload.values_at(:folder, :trashed, :archived, :uid)
        assert_includes server.copied, [ [ 31 ], "Deleted Messages" ]
        assert_includes server.expunged, [ 31 ]

        # The sync finds it in the server's trash, and no longer in the archive folder
        sync = ImapSyncService.new(account)
        sync.send(:fetch_recent_emails, synced_folder([]), "Archive", 50)
        sync.send(:fetch_recent_emails, synced_folder([ [ 50, archived ] ]), "Trash", 50)

        assert_equal [ [ archived.id, "Trash", 50, true ] ], account.messages.where(message_id: archived.message_id).pluck(:id, :folder, :uid, :trashed)
        assert_empty account.archived_messages.where(message_id: archived.message_id)
      end

      test "trashing archived mail once the archive folder has synced leaves one message in the trash" do
        account = @tool.mail_account
        account.update!(synced_folders: %w[INBOX Sent Archive Trash].to_json)
        archived = archived_in_archive_folder
        copy = archive_folder_copy_of(archived, uid: 31)
        clear_enqueued_jobs

        post tool_mail_trash_path(@tool, archived, folder: "archive")

        assert_equal [ [ "Trash", true ] ], account.messages.where(message_id: archived.message_id).pluck(:folder, :trashed)
        assert_includes imap_jobs, [ account.id, "move_to_folder", [ 31 ], "Archive", "Trash" ]
        assert_includes imap_jobs, [ account.id, "move_to_folder_by_message_id", nil, "Archive", "Trash", archived.message_id ]
        assert_not ::Mails::Message.exists?(copy.id) && ::Mails::Message.exists?(archived.id), "one of the two is left"
      end

      test "trashing archived mail on a server without a trash deletes it from the archive folder" do
        archived = archived_in_archive_folder

        post tool_mail_trash_path(@tool, archived, folder: "archive")

        assert_equal [ "INBOX", true, false ], archived.reload.values_at(:folder, :trashed, :archived)
        assert_includes imap_jobs, [ archived.mail_account_id, "delete_message_by_message_id", nil, "Archive", archived.message_id ]
      end

      test "moving archived mail to a folder moves it out of the server's archive folder" do
        archived = archived_in_archive_folder

        post tool_mail_move_path(@tool, archived), params: { folder: "Receipts", current_folder: "archive" }

        assert_equal [ "Receipts", false, nil ], archived.reload.values_at(:folder, :archived, :uid)
        assert_includes imap_jobs, [ archived.mail_account_id, "move_to_folder_by_message_id", nil, "Archive", "Receipts", archived.message_id ]
      end

      test "moving archived mail once the archive folder has synced leaves one message in the folder" do
        archived = archived_in_archive_folder
        archive_folder_copy_of(archived, uid: 31)
        clear_enqueued_jobs

        post tool_mail_move_path(@tool, archived), params: { folder: "Receipts", current_folder: "archive" }

        assert_equal [ [ "Receipts", false, nil ] ], @tool.mail_account.messages.where(message_id: archived.message_id).pluck(:folder, :archived, :uid)
        assert_includes imap_jobs, [ archived.mail_account_id, "move_to_folder", 31, "Archive", "Receipts" ]
        get tool_mails_path(@tool, folder: "archive")
        assert_no_match archived.subject, response.body
      end

      test "mail archived without an archive folder is trashed and moved by its own UID only" do
        archived = mails_messages(:archived_message)

        post tool_mail_move_path(@tool, archived), params: { folder: "Receipts", current_folder: "archive" }
        assert_equal [ [ archived.mail_account_id, "move_to_folder", 106, "INBOX", "Receipts" ] ], imap_jobs

        archived.reload.update!(folder: "INBOX", uid: 106, archived: true)
        clear_enqueued_jobs
        post tool_mail_trash_path(@tool, archived, folder: "archive")
        assert_equal [ [ archived.mail_account_id, "delete_message", [ 106 ], "INBOX" ] ], imap_jobs
      end

      test "unarchiving without an archive folder marks the message unread on the server" do
        msg = mails_messages(:archived_message)

        delete tool_mail_archive_path(@tool, msg)

        assert_enqueued_with job: ImapSyncJob, args: [ msg.mail_account_id, "mark_as_unread", 106, "INBOX" ]
        assert_equal 106, msg.reload.uid
      end

      private

      def imap_jobs
        enqueued_jobs.select { |job| job["job_class"] == "ImapSyncJob" }.map { |job| job["arguments"] }
      end

      # Mail archived here on an account with an archive folder: it keeps its folder and the
      # UID it had there, and the server has it in the archive folder under another UID
      def archived_in_archive_folder
        @tool.mail_account.update!(archive_folder: "Archive")
        # Its Message-ID as the sync saves it, without the angle brackets
        mails_messages(:archived_message).tap { |message| message.update!(message_id: "archived-6@example.com") }
      end

      # The message as the sync saves it from the server's archive folder
      def archive_folder_copy_of(message, uid:)
        @tool.mail_account.update!(archive_folder: "Archive")
        @tool.mail_account.messages.create!(message.attributes.except("id", "created_at", "updated_at").merge("folder" => "Archive", "uid" => uid, "archived" => false))
      end

      # A folder on the server with these messages, as [uid, message] pairs
      def synced_folder(messages)
        fetched = messages.map do |uid, message|
          envelope = Net::IMAP::Envelope.new(nil, message.subject, [ Net::IMAP::Address.new(nil, nil, "colleague", "example.com") ], nil, nil, [], nil, nil, nil, "<#{message.message_id}>")
          raw = Mail.new(from: message.from_address, subject: message.subject, message_id: "<#{message.message_id}>", body: message.body_plain).to_s
          Net::IMAP::FetchData.new(1, { "UID" => uid, "ENVELOPE" => envelope, "FLAGS" => [ :Seen ], "INTERNALDATE" => Time.current, "BODY[]" => raw })
        end
        server = Object.new
        server.define_singleton_method(:uid_search) { |_criteria| fetched.map { |message| message.attr["UID"] } }
        server.define_singleton_method(:uid_fetch) { |uids, _attrs| fetched.select { |message| message.attr["UID"].in?(uids) } }
        server
      end
    end
  end
end

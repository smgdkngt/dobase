# frozen_string_literal: true

require "test_helper"

module Mails
  class AccountTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    setup do
      @account = mails_accounts(:primary)
    end

    test "the archive and trash are synced with the account's own folders, when the server has them" do
      @account.update!(synced_folders: %w[INBOX Sent Archive Clients Trash].to_json, archive_folder: "Archive")
      assert_equal %w[Clients Archive Trash], @account.other_folders_to_sync

      @account.update!(synced_folders: %w[INBOX Sent Archive Clients].to_json, archive_folder: "Done")
      assert_equal %w[Archive Clients], @account.other_folders_to_sync
    end

    test "trashed mail moves to the server's trash, one move per folder, and can come back from there" do
      @account.update!(synced_folders: %w[INBOX Sent Trash].to_json)
      first, second = mails_messages(:inbox_read), mails_messages(:inbox_unread)
      first.update!(uid: 11)
      second.update!(uid: 12)

      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "move_to_folder", [ 11, 12 ], "INBOX", "Trash" ]) do
        @account.trash([ first, second ])
      end
      assert [ first, second ].all? { |message| message.reload.trashed? && message.folder == "Trash" && message.uid.nil? }
      assert_includes @account.messages.trashed, first

      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "move_to_folder_by_message_id", nil, "Trash", "INBOX", first.message_id ]) do
        @account.restore([ first ])
      end
      assert_equal [ "INBOX", false ], [ first.reload.folder, first.trashed? ]
      assert_includes @account.messages.inbox, first
    end

    test "mail deleted for good from the server's trash goes there too" do
      @account.update!(synced_folders: %w[INBOX Trash].to_json)
      synced, just_trashed = mails_messages(:inbox_read), mails_messages(:inbox_unread)
      synced.update!(folder: "Trash", trashed: true, uid: 40)
      just_trashed.update!(folder: "Trash", trashed: true, uid: nil)

      @account.delete_for_good([ synced, just_trashed ])

      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "delete_message", [ 40 ], "Trash" ])
      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "delete_message_by_message_id", nil, "Trash", just_trashed.message_id ])
      assert_not Mails::Message.exists?(synced.id)
      assert_not Mails::Message.exists?(just_trashed.id)
    end

    test "a server without a trash deletes trashed mail right away" do
      message = mails_messages(:inbox_read)
      message.update!(uid: 11)

      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "delete_message", [ 11 ], "INBOX" ]) do
        @account.trash([ message ])
      end
      assert_equal [ "INBOX", true ], [ message.reload.folder, message.trashed? ]
    end
  end
end

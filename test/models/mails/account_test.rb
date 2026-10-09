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

    test "a folder shows without what the server keeps its folders under" do
      @account.update!(folder_prefix: "INBOX.", synced_folders: %w[INBOX Sent INBOX.Receipts INBOX.Clients INBOX.Clients.Acme Notes].to_json)

      assert_equal "Receipts", @account.folder_without_prefix("INBOX.Receipts")
      assert_equal "Clients.Acme", @account.folder_without_prefix("INBOX.Clients.Acme")
      assert_equal "Notes", @account.folder_without_prefix("Notes")
      assert_equal "INBOX", @account.folder_without_prefix("INBOX")
      assert_equal "", @account.folder_without_prefix(nil)
    end

    test "a folder keeps its whole name where the short one is another folder's" do
      @account.update!(folder_prefix: "INBOX.", synced_folders: %w[INBOX Sent INBOX.Sent INBOX.archive INBOX.Notes Notes INBOX.].to_json)

      # The mail page has a Sent and an Archive itself, and the server a Notes beside the inbox
      %w[INBOX.Sent INBOX.archive INBOX.Notes INBOX.].each { |folder| assert_equal folder, @account.folder_without_prefix(folder) }
    end

    test "a server with its folders beside the inbox shows them as they are" do
      [ nil, "" ].each do |prefix|
        @account.update!(folder_prefix: prefix)
        assert_equal "INBOX.Receipts", @account.folder_without_prefix("INBOX.Receipts")
      end
    end

    test "mail moves to a folder by the server's name or by the name it shows under" do
      @account.update!(folder_prefix: "INBOX.", synced_folders: %w[INBOX Sent INBOX.Receipts INBOX.Notes Notes].to_json)

      assert_equal "INBOX.Receipts", @account.folder_to_move_to("INBOX.Receipts")
      assert_equal "INBOX.Receipts", @account.folder_to_move_to("Receipts")
      assert_equal "Notes", @account.folder_to_move_to("Notes")
      assert_equal "INBOX.Notes", @account.folder_to_move_to("INBOX.Notes")
      assert_nil @account.folder_to_move_to("Clients")
      assert_nil @account.folder_to_move_to("")
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

    test "people are known by the name they were written to with, else the one they sign with" do
      @account.record_contact("sender@example.com", "Sandy")
      @account.record_contact("reports@example.com")

      assert_equal({ "sender@example.com" => "Sandy", "reports@example.com" => "Reports Bot" },
        @account.names_for([ "Sender@example.com", "reports@example.com", "stranger@example.com" ]))
    end

    test "the people of a conversation are known by what is at hand: a contact's name, else how they sign in it, and the account's own" do
      @account.record_contact("reports@example.com", "Weekly Reports")
      conversation = [ mails_messages(:inbox_read), mails_messages(:inbox_unread), mails_messages(:sent_message) ]
      mails_messages(:sent_message).update!(from_name: nil, cc_addresses: [ "Reports@example.com", "stranger@example.com" ].to_json)

      assert_equal({ "testuser@example.com" => "Test User", "sender@example.com" => "Friendly Sender", "reports@example.com" => "Weekly Reports" },
        @account.names_in(conversation))
    end

    test "a name someone is written to with is remembered, and who has one keeps it" do
      @account.record_contact("ann@example.com", "Ann Lee")

      @account.remember_names(::Mails::Recipient.parse("Annie <ann@example.com>, Joe Bloggs <joe@example.com>, kim@example.com, Nobody <nobody>"))

      assert_equal({ "ann@example.com" => "Ann Lee", "joe@example.com" => "Joe Bloggs" }, @account.contacts.pluck(:email_address, :name).to_h)
    end
  end
end

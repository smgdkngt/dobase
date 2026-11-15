# frozen_string_literal: true

require "test_helper"

module Mails
  class UndoTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = users(:one)
      @account = mails_accounts(:primary)
      @message = mails_messages(:inbox_unread)
    end

    test "archived mail is back where it was archived from, unread as it was, and the server is told" do
      token = record(:unarchive) { @account.archive(_1) }.token
      assert @message.reload.archived?

      assert_enqueued_jobs 1, only: ImapSyncJob do
        assert_equal 1, find(token).apply
      end
      assert_not @message.reload.archived?
      assert_equal "INBOX", @message.folder
      assert_equal "mail.unarchived", Event.order(:id).last.kind
    end

    test "trashed mail is back in the folder it was trashed from" do
      @account.update!(synced_folders: %w[INBOX Sent Archive Receipts Trash].to_json)
      @message.update!(folder: "Receipts")

      token = record(:put_back) { @account.trash(_1) }.token
      assert_equal [ "Trash", true ], @message.reload.values_at(:folder, :trashed)

      find(token).apply

      assert_equal [ "Receipts", false ], @message.reload.values_at(:folder, :trashed)
      # Straight back, not by way of the inbox: a second move could reach the server before the first
      moves = enqueued_jobs.select { _1["job_class"] == "ImapSyncJob" }.map { _1["arguments"] }.select { _1.second == "move_to_folder_by_message_id" }
      assert_equal [ [ @account.id, "move_to_folder_by_message_id", nil, "Trash", "Receipts", @message.message_id ] ], moves
    end

    test "trashed archived mail is archived again" do
      @account.update!(synced_folders: %w[INBOX Sent Archive Trash].to_json, archive_folder: "Archive")
      archived = mails_messages(:archived_message)

      token = Undo.record(@account, :put_back, [ archived ], user: @user) { @account.trash(_1) }.token
      find(token).apply

      assert_equal "archive", @account.view_of(archived.reload)
    end

    test "moved mail goes back to the folder it was moved from, found on the server by its Message-ID" do
      token = record(:put_back) { @account.move(_1, "Receipts") }.token
      assert_equal "Receipts", @message.reload.folder

      find(token).apply

      assert_equal "INBOX", @message.reload.folder
      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "move_to_folder_by_message_id", nil, "Receipts", "INBOX", @message.message_id ])
    end

    test "junk goes back to where it came from, and mail that wasn't junk to junk" do
      @account.update!(synced_folders: %w[INBOX Sent Junk].to_json)

      find(record(:put_back) { @account.mark_as_junk(_1) }.token).apply
      assert_equal "INBOX", @message.reload.folder

      @message.update!(folder: "Junk")
      find(record(:put_back) { @account.not_junk(_1) }.token).apply
      assert_equal "Junk", @message.reload.folder
    end

    test "several messages are undone together" do
      messages = [ @message, mails_messages(:inbox_read) ]
      token = Undo.record(@account, :unarchive, messages, user: @user) { @account.archive(_1) }.token

      assert_equal 2, find(token).apply
      assert messages.none? { _1.reload.archived? }
    end

    test "only what the action did is undone" do
      archived = mails_messages(:archived_message)
      undo = Undo.record(@account, :unarchive, [ @message, archived ], user: @user) { @account.archive(_1) }

      assert_equal [ @message.id ], undo.places.map(&:first)
    end

    test "a token that was changed, is too old, is someone else's or another tool's undoes nothing" do
      token = record(:unarchive) { @account.archive(_1) }.token

      assert_nil Undo.find(token.succ, account: @account, user: @user)
      assert_nil Undo.find("nonsense", account: @account, user: @user)
      assert_nil Undo.find(nil, account: @account, user: @user)
      assert_nil Undo.find(token, account: @account, user: users(:two))
      assert_nil Undo.find(token, account: mails_accounts(:other), user: @user)
      travel Undo::EXPIRES_IN + 1.second do
        assert_nil Undo.find(token, account: @account, user: @user)
      end
      assert find(token)
    end

    test "a message of another account named in a token is left alone" do
      other = mails_messages(:other_inbox)
      undo = Undo.new(@account, "put_back", [ [ other.id, "Receipts", false ] ], user: @user)

      assert_equal 0, find(undo.token).apply
      assert_equal "INBOX", other.reload.folder
    end

    test "nothing done is nothing to undo" do
      assert_nil Undo.record(@account, :unarchive, [ mails_messages(:archived_message) ], user: @user) { @account.archive(_1) }.token
    end

    private

    def record(kind, &)
      Undo.record(@account, kind, [ @message ], user: @user, &)
    end

    def find(token)
      Undo.find(token, account: @account, user: @user)
    end
  end
end

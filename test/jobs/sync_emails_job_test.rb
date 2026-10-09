# frozen_string_literal: true

require "test_helper"

class SyncEmailsJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @account = mails_accounts(:primary)
  end

  test "a sync that brought mail says so to the pages that have the mailbox open" do
    assert_broadcast_on(pages, type: "changed", tool_id: @account.tool.id) do
      sync_that do
        fresh = mails_messages(:inbox_read).dup
        fresh.update!(message_id: "fresh@example.com", uid: 4711, subject: "Fresh")
      end
    end
  end

  test "a sync that found mail read elsewhere says so too" do
    assert_broadcasts(pages, 1) { sync_that { mails_messages(:inbox_unread).update!(read: true) } }
  end

  test "a sync that brought nothing says nothing" do
    assert_no_broadcasts(pages) { sync_that { } }
  end

  test "a sync that went wrong says so once, for the page to show it" do
    connect_to_imap(ImapServerRejectingLogin.new) do
      assert_broadcasts(pages, 1) { SyncEmailsJob.perform_now(@account.id) }
    end
  end

  test "runs one sync per account at a time and drops the extra requests" do
    assert_equal SyncEmailsJob.new(5).concurrency_key, SyncEmailsJob.new(5).concurrency_key
    assert_not_equal SyncEmailsJob.new(5).concurrency_key, SyncEmailsJob.new(6).concurrency_key
    assert_equal :discard, SyncEmailsJob.concurrency_on_conflict
  end

  test "a wrong password shows as a sync error without failing the job" do
    @account.mark_syncing!

    connect_to_imap(ImapServerRejectingLogin.new) do
      assert_nothing_raised { SyncEmailsJob.perform_now(@account.id) }
    end

    assert @account.reload.sync_error?
    assert @account.authentication_failed?
    assert_equal "The mail server didn't accept the username or password", @account.sync_error
  end

  test "an account whose login was turned down isn't synced again until someone asks" do
    @account.mark_sync_error!(Mails::Account::AUTHENTICATION_FAILED)
    server = ImapServerRejectingLogin.new

    connect_to_imap(server) { SyncEmailsJob.perform_now(@account.id) }
    assert_equal 0, server.logins

    @account.mark_syncing!
    connect_to_imap(server) { SyncEmailsJob.perform_now(@account.id) }
    assert_equal 1, server.logins
  end

  test "an account whose server couldn't be reached is synced again" do
    @account.mark_sync_error!("Connection refused - connect(2) for imap.example.com:993")
    server = ImapServerRejectingLogin.new

    connect_to_imap(server) { SyncEmailsJob.perform_now(@account.id) }

    assert_equal 1, server.logins
  end

  test "a server that can't be found shows as a sync error" do
    @account.update!(imap_host: "imap.example.invalid")
    @account.mark_syncing!

    SyncEmailsJob.perform_now(@account.id)

    assert @account.reload.sync_error?
    assert_equal "imap.example.invalid could not be found", @account.sync_error
  end

  test "a server that drops the connection shows as a sync error without failing the job" do
    @account.mark_syncing!

    connect_to_imap(ImapServerDroppingConnection.new) do
      assert_nothing_raised { SyncEmailsJob.perform_now(@account.id) }
    end

    assert @account.reload.sync_error?
    assert_not @account.authentication_failed?
  end

  private

  def pages
    PresenceChannel.broadcasting_for(@account.tool)
  end

  # A sync in which the server has this to say about the inbox, and nothing else
  def sync_that(&in_the_inbox)
    service = Object.new
    service.define_singleton_method(:sync_folders) { }
    service.define_singleton_method(:sync_inbox) { |**| in_the_inbox.call }
    service.define_singleton_method(:sync_sent) { |**| }
    service.define_singleton_method(:sync_folder) { |*, **| }
    service.define_singleton_method(:record_events) { |**| }
    ImapSyncService.singleton_class.define_method(:new) { |*| service }
    SyncEmailsJob.perform_now(@account.id)
  ensure
    ImapSyncService.singleton_class.remove_method(:new)
  end
    class ImapServerDroppingConnection < FakeImapServer
      def login(_username, _password)
        raise Errno::ECONNRESET, "SSL_connect"
      end
    end

    class ImapServerRejectingLogin < FakeImapServer
      def logins
        @logins || 0
      end

      def login(_username, _password)
        @logins = logins + 1
        text = Net::IMAP::ResponseText.new(nil, "[AUTHENTICATIONFAILED] Invalid credentials (Failure)")
        raise Net::IMAP::NoResponseError, Net::IMAP::TaggedResponse.new("RUBY0001", "NO", text, "")
      end
    end
end

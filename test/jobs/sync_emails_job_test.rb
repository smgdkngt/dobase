# frozen_string_literal: true

require "test_helper"

class SyncEmailsJobTest < ActiveJob::TestCase
  setup do
    @account = mails_accounts(:primary)
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

  private
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

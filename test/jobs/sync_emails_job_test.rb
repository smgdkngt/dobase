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

  test "a wrong password shows as a sync error instead of syncing forever" do
    @account.mark_syncing!

    connect_to_imap(ImapServerRejectingLogin.new) do
      assert_raises(Net::IMAP::NoResponseError) { SyncEmailsJob.perform_now(@account.id) }
    end

    assert @account.reload.sync_error?
    assert_equal "[AUTHENTICATIONFAILED] Invalid credentials (Failure)", @account.sync_error
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
      def login(_username, _password)
        text = Net::IMAP::ResponseText.new(nil, "[AUTHENTICATIONFAILED] Invalid credentials (Failure)")
        raise Net::IMAP::NoResponseError, Net::IMAP::TaggedResponse.new("RUBY0001", "NO", text, "")
      end
    end
end

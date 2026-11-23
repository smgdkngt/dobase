# frozen_string_literal: true

require "test_helper"

class Mails::IdleWatcherTest < ActiveJob::TestCase
  class IdlingServer
    attr_reader :timeouts, :selected

    def initialize(steps, capabilities: %w[IMAP4REV1 IDLE], last_uid: 4711)
      @steps = steps
      @capabilities = capabilities
      @last_uid = last_uid
      @timeouts = []
      @selected = []
    end

    def login(*) = nil
    def logout = nil
    def disconnect = nil
    def idle_done = nil
    def capable?(capability) = @capabilities.include?(capability)
    def select(folder) = @selected << folder

    def fetch(sequence_number, _attrs)
      raise Net::IMAP::BadResponseError, Net::IMAP::TaggedResponse.new("A1", "BAD", Net::IMAP::ResponseText.new(nil, "Parse Error"), "") if @last_uid == :refused

      [ Net::IMAP::FetchData.new(sequence_number, { "UID" => @last_uid }) ]
    end

    def idle(timeout, &block)
      @timeouts << timeout
      @steps.shift&.call(block)
    end
  end

  setup do
    @account = mails_accounts(:primary)
    @watcher = Mails::IdleWatcher.new(@account.id, debounce: 0)
    @rests = []
    rests = @rests
    @watcher.define_singleton_method(:rest) do |seconds|
      rests << seconds
      @stopped = true unless seconds.zero?
    end
  end

  test "new mail the server tells of is synced at once, and again until it is in" do
    server = IdlingServer.new([
      ->(heard) { heard.call(Net::IMAP::UntaggedResponse.new("EXISTS", 12, "")) },
      ->(_) { },
      ->(_) { arrived(4711) },
      ->(_) { @watcher.stop }
    ])

    connect_to_imap(server) { @watcher.run }

    assert_equal [ "INBOX" ], server.selected
    assert_enqueued_jobs 3, only: SyncEmailsJob
    assert_equal [ 10.minutes, 20.seconds, 20.seconds, 10.minutes ], server.timeouts
  end

  test "mail read or removed elsewhere is synced too" do
    server = IdlingServer.new([
      ->(heard) { heard.call(Net::IMAP::UntaggedResponse.new("EXPUNGE", 3, "")) },
      ->(_) { @watcher.stop }
    ], last_uid: 1)

    connect_to_imap(server) { @watcher.run }

    assert_enqueued_jobs 2, only: SyncEmailsJob
  end

  test "what else the server says while idling is no reason to sync" do
    server = IdlingServer.new([
      ->(heard) { heard.call(Net::IMAP::ContinuationRequest.new(Net::IMAP::ResponseText.new(nil, "idling"), "")) },
      ->(_) { @watcher.stop }
    ])

    connect_to_imap(server) { @watcher.run }

    assert_enqueued_jobs 1, only: SyncEmailsJob
  end

  test "new mail is synced also when the server won't say its UID" do
    server = IdlingServer.new([
      ->(heard) { heard.call(Net::IMAP::UntaggedResponse.new("EXISTS", 12, "")) },
      ->(_) { @watcher.stop }
    ], last_uid: :refused)

    connect_to_imap(server) { @watcher.run }

    assert_enqueued_jobs 2, only: SyncEmailsJob
    assert_equal [ 10.minutes, 10.minutes ], server.timeouts
    assert_equal [ 0 ], @rests
  end

  test "a server without IDLE is left to the scheduled sync" do
    server = IdlingServer.new([], capabilities: %w[IMAP4REV1])

    connect_to_imap(server) { @watcher.run }

    assert_empty server.timeouts
    assert_no_enqueued_jobs only: SyncEmailsJob
    assert_equal [ 1.hour ], @rests
  end

  test "a refused login is not tried again before the scheduled sync would" do
    connect_to_imap(FakeImapServer.new(refuses_login: "[AUTHENTICATIONFAILED] Invalid credentials")) { @watcher.run }

    assert_no_enqueued_jobs only: SyncEmailsJob
    assert_equal [ EncryptedPassword::LOGIN_RETRY ], @rests
  end

  test "an account waiting after a refused login is not logged in to" do
    @account.mark_sync_error!(Mails::Account::AUTHENTICATION_FAILED)
    server = IdlingServer.new([])

    connect_to_imap(server) { @watcher.run }

    assert_empty server.selected
    assert_equal [ EncryptedPassword::LOGIN_RETRY ], @rests
  end

  test "a dropped connection is tried again after a while" do
    server = IdlingServer.new([ ->(_) { raise EOFError, "end of file reached" } ])

    connect_to_imap(server) { @watcher.run }

    assert_equal 1, @rests.size
    assert_includes 10.seconds..15.seconds, @rests.first
  end

  private
    def arrived(uid)
      mails_messages(:inbox_read).dup.update!(message_id: "arrived-#{uid}@example.com", uid: uid, folder: "INBOX")
    end
end

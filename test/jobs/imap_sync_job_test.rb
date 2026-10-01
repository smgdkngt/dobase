# frozen_string_literal: true

require "test_helper"

# What's changed in Dobase is changed on the mail server afterwards. While the server can't
# be reached that's tried again, and never in a way that would make a change twice.
class ImapSyncJobTest < ActiveJob::TestCase
  setup do
    @account = mails_accounts(:primary)
    @account.update!(synced_folders: %w[INBOX Sent Trash].to_json)
    @server = FakeImapServer.new(folders: [ "INBOX", "Receipts", [ "Deleted Messages", :Trash ] ])
  end

  test "mail trashed while the server can't be reached is moved to its trash once it can" do
    message = mails_messages(:inbox_read)
    attempts = 0

    with_imap_server(-> { (attempts += 1) < 3 }) do
      perform_enqueued_jobs(only: ImapSyncJob) { @account.trash([ message ]) }
    end

    assert_equal 3, attempts
    assert_equal [ [ [ 102 ], "Deleted Messages" ] ], @server.copied
    assert_equal [ [ 102 ] ], @server.expunged
    assert_equal [ "Trash", true ], [ message.reload.folder, message.trashed? ]
  end

  test "a change is given up on when the server stays out of reach, without failing the job" do
    attempts = 0

    with_imap_server(-> { attempts += 1 }) do
      assert_nothing_raised do
        perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "move_to_folder", 102, "INBOX", "Receipts") }
      end
    end

    assert_equal 5, attempts
    assert_empty @server.copied
    assert_no_enqueued_jobs only: ImapSyncJob
  end

  test "every change is tried again while the server can't be reached" do
    changes = [
      [ "mark_as_read", 102, "INBOX" ], [ "mark_as_unread", 102, "INBOX" ], [ "set_starred", 102, "INBOX", true ],
      [ "move_to_folder", 102, "INBOX", "Receipts" ], [ "move_to_folder_by_message_id", nil, "Trash", "INBOX", "msg-002@example.com" ],
      [ "delete_message", [ 105 ], "INBOX" ], [ "delete_message_by_message_id", nil, "Trash", "msg-002@example.com" ], [ "delete_draft", 55, "Drafts" ]
    ]

    changes.each do |change|
      attempts = 0
      with_imap_server(-> { (attempts += 1) < 2 }) do
        perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, *change) }
      end

      assert_equal 2, attempts, change.first
    end
  end

  test "a move whose copy was on its way when the connection broke isn't made again" do
    copies = 0
    @server.define_singleton_method(:uid_copy) { |*| copies += 1; raise Errno::ECONNRESET }

    connect_to_imap(@server) do
      perform_enqueued_jobs(only: ImapSyncJob) do
        ImapSyncJob.perform_later(@account.id, "move_to_folder", 102, "INBOX", "Receipts")
        ImapSyncJob.perform_later(@account.id, "move_to_folder_by_message_id", nil, "Trash", "INBOX", "msg-002@example.com")
      end
    end

    assert_equal 1, copies, "only the move by UID found its message"
    assert_no_enqueued_jobs only: ImapSyncJob
  end

  test "a move by Message-ID whose copy was on its way when the connection broke isn't made again" do
    server = FakeImapServer.new(folders: [ "INBOX", "Trash" ], message_ids: { [ "Trash", "<msg-002@example.com>" ] => [ 31 ] })
    copies = 0
    server.define_singleton_method(:uid_copy) { |*| copies += 1; raise EOFError, "end of file reached" }

    connect_to_imap(server) do
      perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "move_to_folder_by_message_id", nil, "Trash", "INBOX", "msg-002@example.com") }
    end

    assert_equal 1, copies
  end

  test "a move that was copied isn't copied again when removing it from its old folder breaks" do
    removals = 0
    @server.define_singleton_method(:uid_expunge) { |*| removals += 1; raise Errno::EPIPE }

    connect_to_imap(@server) do
      perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "move_to_folder", 102, "INBOX", "Receipts") }
    end

    assert_equal [ [ 102, "Receipts" ] ], @server.copied
    assert_equal 1, removals
  end

  test "a move that broke before anything was copied is made once" do
    selects = 0
    select = @server.method(:select)
    @server.define_singleton_method(:select) { |folder| (selects += 1) == 1 ? raise(IOError, "closed stream") : select.call(folder) }

    connect_to_imap(@server) do
      perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "move_to_folder", 102, "INBOX", "Receipts") }
    end

    assert_equal [ [ 102, "Receipts" ] ], @server.copied
  end

  test "deleting is done again when the connection broke halfway: twice comes to the same" do
    expunges = 0
    expunge = @server.method(:uid_expunge)
    @server.define_singleton_method(:uid_expunge) { |uids| (expunges += 1) == 1 ? raise(Errno::ECONNRESET) : expunge.call(uids) }

    connect_to_imap(@server) do
      perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "delete_message", [ 105 ], "INBOX") }
    end

    assert_equal [ [ [ 105 ], "+FLAGS", [ :Deleted ] ] ] * 2, @server.stored
    assert_equal [ [ 105 ] ], @server.expunged
  end

  # A server without a trash deletes trashed mail. Restored in the meantime, it must stay.

  test "mail restored while its deletion waited for the server isn't deleted there" do
    @account.update!(synced_folders: %w[INBOX Sent].to_json)
    restored, trashed = mails_messages(:inbox_read), mails_messages(:inbox_unread)

    with_imap_server(-> { true }) do
      @account.trash([ restored, trashed ])
      perform_enqueued_jobs(only: ImapSyncJob, at: Time.current)
    end
    assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "delete_message", [ 102, 101 ], "INBOX" ])

    @account.restore([ restored.reload ])
    # The inbox's sync found it on the server, and gave it its UID again
    restored.update!(uid: 102)
    connect_to_imap(@server) { perform_enqueued_jobs(only: ImapSyncJob) }

    assert_equal [ [ [ 101 ], "+FLAGS", [ :Deleted ] ] ], @server.stored
    assert_equal [ [ 101 ] ], @server.expunged
  end

  test "a change the server turns down isn't tried again" do
    stores = 0
    @server.define_singleton_method(:uid_store) do |*|
      stores += 1
      raise Net::IMAP::NoResponseError, Net::IMAP::TaggedResponse.new("RUBY0001", "NO", Net::IMAP::ResponseText.new(nil, "Mailbox is read-only"), "")
    end

    connect_to_imap(@server) do
      assert_nothing_raised { perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "mark_as_read", 102, "INBOX") } }
    end

    assert_equal 1, stores
  end

  test "a change isn't tried again when the server doesn't accept the password" do
    logins = 0
    @server.define_singleton_method(:login) do |*|
      logins += 1
      raise Net::IMAP::NoResponseError, Net::IMAP::TaggedResponse.new("RUBY0001", "NO", Net::IMAP::ResponseText.new(nil, "Invalid credentials"), "")
    end

    connect_to_imap(@server) do
      assert_nothing_raised { perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "mark_as_read", 102, "INBOX") } }
    end

    assert_equal 1, logins
  end

  test "a server whose name can't be looked up for a moment is tried again" do
    lookups = 0
    failure = Socket::ResolutionError.new("getaddrinfo: Temporary failure in name resolution")
    failure.define_singleton_method(:error_code) { Socket::EAI_AGAIN }
    resolver = RemoteHost.resolver
    RemoteHost.resolver = ->(host) { (lookups += 1) == 1 ? raise(failure) : resolver.call(host) }

    connect_to_imap(@server) do
      perform_enqueued_jobs(only: ImapSyncJob) { ImapSyncJob.perform_later(@account.id, "mark_as_read", 102, "INBOX") }
    end

    assert_equal 2, lookups
    assert_equal [ [ 102, "+FLAGS", [ :Seen ] ] ], @server.stored
  ensure
    RemoteHost.resolver = resolver
  end

  test "a draft is saved on the server once it can be reached" do
    draft = mails_messages(:draft_message)
    server = FakeImapServer.new(folders: [ "INBOX", "Drafts" ])
    attempts = 0

    with_imap_server(-> { (attempts += 1) < 3 }, server) do
      perform_enqueued_jobs(only: SyncDraftJob) { SyncDraftJob.perform_later(draft.id) }
    end

    assert_equal 3, attempts
    assert_equal [ [ "Drafts", [ :Draft, :Seen ] ] ], server.appended
  end

  test "a draft that was on its way when the connection broke isn't saved again" do
    draft = mails_messages(:draft_message)
    server = FakeImapServer.new(folders: [ "INBOX", "Drafts" ])
    appends = 0
    server.define_singleton_method(:append) { |*| appends += 1; raise Errno::ECONNRESET }

    connect_to_imap(server) do
      assert_nothing_raised { perform_enqueued_jobs(only: SyncDraftJob) { SyncDraftJob.perform_later(draft.id) } }
    end

    assert_equal 1, appends
  end

  private

  # A mail server that refuses the connection while unreachable returns true
  def with_imap_server(unreachable, server = @server)
    Net::IMAP.singleton_class.define_method(:new) do |*, **|
      raise Errno::ECONNREFUSED, "connect(2) for imap.example.com:993" if unreachable.call
      server
    end
    yield
  ensure
    Net::IMAP.singleton_class.remove_method(:new)
  end
end

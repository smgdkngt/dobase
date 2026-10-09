# frozen_string_literal: true

require "test_helper"

module Mails
  # What a run of the mail sync writes down as events: mail that came in, and what
  # another mail program did. Each test is one run: folders as the server has them
  # now, synced in the order SyncEmailsJob syncs them.
  class SyncEventsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ActionCable::TestHelper

    setup do
      @account = mails_accounts(:primary)
      @account.update!(archive_folder: "Archive", synced_folders: %w[INBOX Sent Archive Receipts Trash].to_json)
      # Synced mail is kept by its Message-ID without the angle brackets
      @account.messages.not_draft.each { |message| message.update_columns(message_id: message.message_id.delete("<>")) }
      # The inbox and sent mail as the fixtures have them. The inbox has given 106 numbers so far.
      @inbox = { 101 => "msg-001", 102 => "msg-002", 103 => "msg-003" }
      @sent = { 104 => "msg-004" }
    end

    test "mail that came in since the last sync is received" do
      events = run_of("INBOX" => @inbox.merge(204 => "fresh"))

      event = events.sole
      message = @account.messages.find_by!(message_id: "fresh@example.com")
      assert_equal [ "mail.received", @account.tool_id, message.id, nil ], event.values_at(:kind, :tool_id, :record_id, :user_id)
      assert_equal({ "from" => "ann@example.com", "from_name" => "Ann", "subject" => "fresh", "folder" => "INBOX" }, event.data)
    end

    test "an event says who a mail is from and what it is called, never what it says" do
      events = run_of("INBOX" => @inbox.merge(204 => "fresh"))

      assert_equal "The body, which is nobody's business", @account.messages.find_by!(message_id: "fresh@example.com").body_plain
      assert_no_match(/nobody's business/, events.sole.attributes.to_json)
    end

    test "several mails come in oldest first" do
      events = run_of("INBOX" => @inbox.merge(204 => [ "second", 1.minute.ago ], 205 => [ "first", 3.minutes.ago ]))

      assert_equal %w[first second], events.map { |event| event.data["subject"] }
      assert_equal %w[mail.received], events.map(&:kind).uniq
    end

    test "mail a filter put in a folder of its own is received there" do
      events = run_of("INBOX" => @inbox, "Receipts" => { 1 => "invoice" })

      assert_equal [ [ "mail.received", "Receipts" ] ], events.map { |event| [ event.kind, event.data["folder"] ] }
    end

    test "the first sync of an account brings its mail, which is not news" do
      @account.update!(last_synced_at: nil)
      @account.messages.destroy_all

      assert_empty run_of("INBOX" => { 1 => "old-1", 2 => "old-2" })
    end

    test "old mail that comes into view is not new mail" do
      # A lower number than the folder had: mail from before, synced only now
      assert_empty run_of("INBOX" => @inbox.merge(55 => [ "backfilled", 1.minute.ago ]))
    end

    test "mail another program put in a folder with an old date is not new mail" do
      assert_empty run_of("INBOX" => @inbox.merge(204 => [ "imported", 3.weeks.ago ]))
    end

    test "mail that arrived while syncing was down is received when it works again" do
      @account.update!(last_synced_at: 3.days.ago)

      events = run_of("INBOX" => @inbox.merge(204 => [ "waited", 2.days.ago ]))

      assert_equal %w[mail.received], events.map(&:kind)
    end

    test "mail sent from another program, a draft or what is thrown away there has not come in" do
      events = run_of("INBOX" => @inbox, "Sent" => @sent.merge(109 => "sent-elsewhere"), "Trash" => { 4 => "junked" })

      assert_empty events
    end

    test "mail to yourself is in Sent and comes in as well" do
      run_of("INBOX" => @inbox, "Sent" => @sent.merge(109 => "note-to-self"))

      events = run_of("INBOX" => @inbox.merge(204 => "note-to-self"), "Sent" => @sent.merge(109 => "note-to-self"))

      assert_equal [ [ "mail.received", "INBOX" ] ], events.map { |event| [ event.kind, event.data["folder"] ] }
    end

    test "mail another program moved is one move, whichever folder is synced first" do
      events = run_of("INBOX" => @inbox.except(102), "Receipts" => { 7 => "msg-002" })

      message = @account.messages.find_by!(message_id: "msg-002@example.com")
      assert_equal [ [ "mail.moved", message.id, "Receipts", "INBOX" ] ],
        events.map { |event| [ event.kind, event.record_id, event.data["folder"], event.data["moved_from"] ] }

      events = run_of("INBOX" => @inbox.except(102).merge(204 => "msg-002"), "Receipts" => {})
      assert_equal [ [ "mail.moved", "INBOX", "Receipts" ] ], events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }
    end

    test "mail another program archived, brought back or threw away" do
      events = run_of("INBOX" => @inbox.except(102), "Archive" => { 3 => "msg-002" })
      assert_equal [ [ "mail.archived", "Archive", "INBOX" ] ], events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }

      events = run_of("INBOX" => @inbox.except(102).merge(204 => "msg-002"), "Archive" => {})
      assert_equal [ [ "mail.unarchived", "INBOX", "Archive" ] ], events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }

      events = run_of("INBOX" => @inbox.except(102), "Trash" => { 8 => "msg-002" })
      assert_equal [ [ "mail.deleted", "Trash", "INBOX" ] ], events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }
    end

    test "mail that is gone from its folder and nowhere else is deleted" do
      gone = mails_messages(:inbox_read)

      events = run_of("INBOX" => @inbox.except(102))

      assert_equal [ [ "mail.deleted", gone.id, { "from" => "reports@example.com", "from_name" => "Reports Bot", "subject" => "Your weekly report", "folder" => "INBOX" } ] ],
        events.map { |event| [ event.kind, event.record_id, event.data ] }
    end

    test "mail gone from a run that didn't get through every folder may be in one it didn't read" do
      assert_empty run_of("INBOX" => @inbox.except(102), complete: false)
    end

    # A run fetches so much new mail per folder (ImapSyncService::BACKFILL_BATCH): the rest
    # of what was moved there is on the server, where this run didn't look
    test "more mail moved by another program than one run reads is not deleted mail" do
      stub_const(ImapSyncService, :BACKFILL_BATCH, 1) do
        events = run_of("INBOX" => {}, "Receipts" => { 7 => "msg-001", 8 => "msg-002", 9 => "msg-003" })

        assert_equal [ [ "mail.moved", "msg-003", "Receipts", "INBOX" ] ],
          events.map { |event| [ event.kind, event.data["subject"], event.data["folder"], event.data["moved_from"] ] }

        moved = { 7 => [ "msg-001", 2.days.ago ], 8 => [ "msg-002", 2.days.ago ], 9 => [ "msg-003", 2.days.ago ] }
        assert_empty run_of("INBOX" => {}, "Receipts" => moved)
        assert_empty run_of("INBOX" => {}, "Receipts" => moved)
        assert_equal 3, @account.messages.where(folder: "Receipts").count
      end
    end

    test "a folder whose old mail is still coming into view doesn't keep deleted mail from being said" do
      stub_const(ImapSyncService, :BACKFILL_BATCH, 1) do
        filling = { 1 => [ "old-1", 2.years.ago ], 2 => [ "old-2", 2.years.ago ], 50 => [ "old-50", 2.years.ago ] }
        assert_empty run_of("INBOX" => @inbox, "Receipts" => filling)

        gone = mails_messages(:inbox_read).id

        events = run_of("INBOX" => @inbox.except(102), "Receipts" => filling)

        assert_equal [ [ "mail.deleted", gone ] ], events.map { |event| [ event.kind, event.record_id ] }
      end
    end

    test "a run keeps of the mail it saw who it is from and what it is called, not what it says" do
      service = ImapSyncService.new(@account)
      service.send(:fetch_recent_emails, FakeImap.new([ fetch_data(204, "fresh", 1.minute.ago) ]), "INBOX", 50)
      service.send(:fetch_recent_emails, FakeImap.new([]), "Receipts", 50)

      seen = service.send(:sync_events)
      kept = seen.instance_variable_get(:@arrived).map(&:message) + seen.instance_variable_get(:@left)
      assert_equal 4, kept.size
      kept.each { |message| assert_equal Mails::SyncEvents::KEPT.sort, message.attributes.keys.sort }
    end

    test "a run that saw a lot says so once" do
      signals = capture_broadcasts(EventsChannel.stream_name(users(:one).id)) do
        run_of("INBOX" => @inbox.merge(204 => "one", 205 => "two", 206 => "three"))
      end

      assert_equal [ Event.maximum(:id) ], signals.map { |signal| signal["id"] }
      assert_equal 3, Event.where(kind: "mail.received").count
    end

    test "mail that came in is said even when the run stopped halfway" do
      events = run_of("INBOX" => @inbox.merge(204 => "fresh"), complete: false)

      assert_equal %w[mail.received], events.map(&:kind)
    end

    test "the trash emptied by the server is no event: its mail was deleted when it went in" do
      run_of("INBOX" => @inbox, "Trash" => { 8 => "junk" })

      assert_empty run_of("INBOX" => @inbox, "Trash" => {})
    end

    test "mail archived here gets a copy in the server's archive folder, which is nothing new" do
      mails_messages(:inbox_read).update!(archived: true)

      events = run_of("INBOX" => @inbox.except(102), "Archive" => { 3 => "msg-002" })

      assert_empty events
      assert_equal 2, @account.messages.where(message_id: "msg-002@example.com").count
    end

    test "mail moved here is not moved again by the sync that finds it on the server" do
      mails_messages(:inbox_read).move_to_folder!("Receipts")

      events = run_of("INBOX" => @inbox.except(102), "Receipts" => { 7 => "msg-002" })

      assert_empty events
      assert_equal [ [ "Receipts", 7 ] ], @account.messages.where(message_id: "msg-002@example.com").pluck(:folder, :uid)
    end

    test "mail trashed here is not deleted again by the sync that finds it in the server's trash" do
      @account.trash([ mails_messages(:inbox_read) ])

      assert_empty run_of("INBOX" => @inbox.except(102), "Trash" => { 8 => "msg-002" })
    end

    test "the sync job writes down what its run saw" do
      service = ImapSyncService.new(@account)
      recorded = nil
      %i[sync_folders sync_inbox sync_sent].each { |step| service.define_singleton_method(step) { |**| } }
      service.define_singleton_method(:sync_folder) { |*, **| }
      service.define_singleton_method(:record_events) { |complete:| recorded = complete }
      ImapSyncService.singleton_class.define_method(:new) { |*| service }

      SyncEmailsJob.perform_now(@account.id)
      assert_equal true, recorded

      service.define_singleton_method(:sync_sent) { |**| raise Errno::ECONNRESET }
      SyncEmailsJob.perform_now(@account.id)
      assert_equal false, recorded
    ensure
      ImapSyncService.singleton_class.remove_method(:new)
    end

    private
      # One run of the sync over these folders: { folder => { uid => message id, or [ id, when the server took it in ] } }
      def run_of(complete: true, **folders)
        before = Event.maximum(:id).to_i
        service = ImapSyncService.new(@account)
        folders.each do |folder, mail|
          messages = mail.map { |uid, (id, received_at)| fetch_data(uid, id, received_at || 1.minute.ago) }
          service.send(:fetch_recent_emails, FakeImap.new(messages), folder, 50)
        end
        service.record_events(complete: complete)
        @account.update!(last_synced_at: Time.current)
        Event.where(id: (before + 1)..).order(:id).to_a
      end

      class FakeImap
        def initialize(messages)
          @messages = messages
        end

        def uid_search(_criteria) = @messages.map { |message| message.attr["UID"] }

        def uid_fetch(uids, _attrs) = @messages.select { |message| message.attr["UID"].in?(uids) }
      end

      # A message as net-imap hands it over. The server's INTERNALDATE comes as text.
      def fetch_data(uid, id, received_at)
        raw = Mail.new(from: "Ann <ann@example.com>", to: "me@example.com", subject: id, message_id: "<#{id}@example.com>",
          body: "The body, which is nobody's business").to_s
        envelope = Net::IMAP::Envelope.new(
          nil, id, [ Net::IMAP::Address.new("Ann", nil, "ann", "example.com") ], nil, nil,
          [ Net::IMAP::Address.new(nil, nil, "me", "example.com") ], nil, nil, nil, "<#{id}@example.com>"
        )
        Net::IMAP::FetchData.new(1, { "UID" => uid, "ENVELOPE" => envelope, "FLAGS" => [],
          "INTERNALDATE" => received_at.strftime("%d-%b-%Y %H:%M:%S %z"), "BODY[]" => raw })
      end
  end
end

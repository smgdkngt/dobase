# frozen_string_literal: true

require "test_helper"

class ImapSyncServiceTest < ActiveSupport::TestCase
  setup do
    @account = mails_accounts(:primary)
    @service = ImapSyncService.new(@account)
  end

  # --- Reconciliation ---------------------------------------------------------
  # Locks in the documented invariant: ImapSyncService reconciles INBOX/Sent
  # against the server's UID list, but skips trashed/archived/draft rows and
  # rows without a uid. These are kept locally on purpose so they remain
  # visible in their respective views.

  test "destroys local INBOX messages no longer present on the server" do
    assert_difference -> { reconcilable_inbox_ids.count }, -2 do
      reconcile("INBOX", [ 101 ])
    end

    assert ::Mails::Message.exists?(uid: 101, folder: "INBOX")
    refute ::Mails::Message.exists?(uid: 102, folder: "INBOX")
    refute ::Mails::Message.exists?(uid: 103, folder: "INBOX")
  end

  test "keeps trashed messages even when missing from the server" do
    trashed = mails_messages(:trashed_message)
    assert_equal "INBOX", trashed.folder
    assert trashed.trashed?

    reconcile("INBOX", [])

    assert ::Mails::Message.exists?(trashed.id)
  end

  test "keeps archived messages even when missing from the server" do
    archived = mails_messages(:archived_message)
    assert archived.archived?

    reconcile("INBOX", [])

    assert ::Mails::Message.exists?(archived.id)
  end

  test "keeps draft messages even when missing from the server" do
    draft = mails_messages(:draft_message)
    assert draft.draft?

    reconcile("INBOX", [])

    assert ::Mails::Message.exists?(draft.id)
  end

  test "keeps messages without a uid during reconciliation" do
    pending = @account.messages.create!(
      message_id: "<pending@local>",
      folder: "INBOX",
      from_address: "x@example.com",
      to_addresses: "[]",
      sent_at: Time.current
    )

    reconcile("INBOX", [])

    assert ::Mails::Message.exists?(pending.id)
  end

  test "destroys every reconcilable row when the server is empty" do
    assert_difference -> { reconcilable_inbox_ids.count }, -3 do
      reconcile("INBOX", [])
    end
  end

  test "only affects the named folder" do
    sent_id = mails_messages(:sent_message).id

    reconcile("INBOX", [])

    assert ::Mails::Message.exists?(sent_id), "Sent message should not be touched by INBOX reconciliation"
  end

  # --- Calendar invites -------------------------------------------------------
  # save_email has already stored the email by the time invites are detected,
  # so a broken invite must not raise and abort the rest of the batch.

  test "an invite that fails to load does not raise out of the sync" do
    email = mails_messages(:inbox_unread)
    attachment = email.attachments.create!(filename: "invite.ics", content_type: "text/calendar")
    attachment.file.attach(io: StringIO.new("BEGIN:VCALENDAR"), filename: "invite.ics", content_type: "text/calendar")
    attachment.file.blob.service.delete(attachment.file.blob.key)

    assert_nothing_raised { @service.send(:detect_calendar_invite, email) }
    assert_empty email.calendar_invites
  end

  # --- Sent folder detection --------------------------------------------------

  test "the sent folder is found by a name servers commonly use" do
    assert_equal "Sent", special_folder("Sent", %w[INBOX Sent Trash])
    assert_equal "[Gmail]/Sent Mail", special_folder("Sent", [ "INBOX", "[Gmail]/Sent Mail" ])
    assert_equal "INBOX.Sent", special_folder("Sent", %w[INBOX INBOX.Sent INBOX.Trash])
    assert_nil special_folder("Sent", %w[INBOX Trash])
  end

  test "the drafts folder is found by a name servers commonly use" do
    assert_equal "[Gmail]/Drafts", special_folder("Drafts", [ "INBOX", "[Gmail]/Drafts" ])
    assert_equal "INBOX.Drafts", special_folder("Drafts", %w[INBOX INBOX.Drafts])
    assert_nil special_folder("Drafts", %w[INBOX Trash])
  end

  test "a folder the server marks with a SPECIAL-USE attribute comes before names" do
    folders = [ "INBOX", "Drafts", "Sent", [ "[Gmail]/Concepten", :Drafts ], [ "[Gmail]/Verzonden berichten", :Sent ] ]

    assert_equal "[Gmail]/Concepten", special_folder("Drafts", folders)
    assert_equal "[Gmail]/Verzonden berichten", special_folder("Sent", folders)
    assert_nil special_folder("Receipts", folders)
  end

  # Sent mail is stored in "Sent", which isn't the sent folder's name on Gmail, iCloud or Office 365

  test "changes to sent mail happen in the server's sent folder" do
    server = FakeImapServer.new(folders: [ "INBOX", "[Gmail]/Sent Mail", "Receipts" ])

    connect_to_imap(server) do
      @service.mark_as_read(104, folder: "Sent")
      @service.mark_as_unread(104, folder: "Sent")
      @service.set_starred(104, true, folder: "Sent")
      @service.delete_message(104, folder: "Sent")
    end

    assert_equal [ "[Gmail]/Sent Mail" ] * 4, server.selected
    assert_equal [ [ 104, "+FLAGS", [ :Seen ] ], [ 104, "-FLAGS", [ :Seen ] ], [ 104, "+FLAGS", [ :Flagged ] ], [ 104, "+FLAGS", [ :Deleted ] ] ], server.stored
  end

  test "moving mail to and from the sent folder uses the server's name, listing folders once per move" do
    server = FakeImapServer.new(folders: [ "INBOX", "Sent Items" ])

    connect_to_imap(server) do
      @service.move_to_folder(104, source_folder: "Sent", destination_folder: "INBOX")
      @service.move_to_folder(7, source_folder: "INBOX", destination_folder: "Sent")
    end

    assert_equal [ "Sent Items", "INBOX" ], server.selected
    assert_equal [ [ 104, "INBOX" ], [ 7, "Sent Items" ] ], server.copied
    assert_equal 2, server.lists
  end

  test "other folders are used by their own name, without listing folders" do
    server = FakeImapServer.new(folders: [ "INBOX", "Sent Messages", "Receipts" ])

    connect_to_imap(server) do
      @service.mark_as_read(101, folder: "INBOX")
      @service.move_to_folder(101, source_folder: "INBOX", destination_folder: "Receipts")
    end

    assert_equal [ "INBOX", "INBOX" ], server.selected
    assert_equal [ [ 101, "Receipts" ] ], server.copied
    assert_equal 0, server.lists
  end

  test "a server without a known sent folder gets the name Sent" do
    server = FakeImapServer.new(folders: [ "INBOX", "Outbox" ])

    connect_to_imap(server) { @service.mark_as_read(104, folder: "Sent") }

    assert_equal [ "Sent" ], server.selected
  end

  # Drafts are stored in "Drafts", which is "[Gmail]/Drafts" on Gmail and "INBOX.Drafts" on Cyrus-style servers

  test "deleting a draft happens in the server's drafts folder" do
    server = FakeImapServer.new(folders: [ "INBOX", [ "[Gmail]/Drafts", :Drafts ] ])

    connect_to_imap(server) do
      @service.delete_message(55, folder: "Drafts")
      @service.delete_draft(56)
      @service.delete_draft(nil)
    end

    assert_equal [ "[Gmail]/Drafts" ] * 2, server.selected
    assert_equal [ 55, 56 ], server.expunged
  end

  test "a draft is saved in the server's drafts folder" do
    draft = mails_messages(:draft_message)
    server = FakeImapServer.new(folders: [ "INBOX", "INBOX.Drafts" ], message_ids: { [ "INBOX.Drafts", draft.message_id ] => [ 9 ] })

    connect_to_imap(server) { @service.save_draft(draft) }

    assert_equal [ [ "INBOX.Drafts", [ :Draft, :Seen ] ] ], server.appended
    assert_equal 9, draft.reload.uid
  end

  test "the server's sent and drafts folders are listed as Sent and Drafts" do
    server = FakeImapServer.new(folders: [ "INBOX", "Receipts", [ "[Gmail]/Sent Mail", :Sent ], "[Gmail]/Drafts", "[Gmail]/Spam" ])

    connect_to_imap(server) { @service.sync_folders }

    assert_equal %w[INBOX Receipts Sent Drafts], JSON.parse(@account.reload.synced_folders)
  end

  # --- Moving mail by Message-ID ----------------------------------------------
  # A moved message gets a new UID in its new folder, so the UID stored before the
  # move can belong to another message there.

  test "mail is found by its whole Message-ID and moved" do
    server = FakeImapServer.new(folders: [ "INBOX", "Archive" ], message_ids: { [ "Archive", "<msg-006@example.com>" ] => [ 12 ] })

    connect_to_imap(server) do
      @service.move_to_folder_by_message_id("msg-006@example.com", source_folder: "Archive", destination_folder: "INBOX")
    end

    assert_equal [ "Archive" ], server.selected
    assert_equal [ [ "HEADER", "Message-ID", "<msg-006@example.com>" ] ], server.searched
    assert_equal [ [ [ 12 ], "INBOX" ] ], server.copied
    assert_equal [ [ [ 12 ], "+FLAGS", [ :Deleted ] ] ], server.stored
  end

  test "mail that isn't in the folder anymore is left alone" do
    server = FakeImapServer.new(folders: [ "INBOX", "Archive" ])

    connect_to_imap(server) do
      @service.move_to_folder_by_message_id("<gone@example.com>", source_folder: "Archive", destination_folder: "INBOX")
    end

    assert_equal [ [ "HEADER", "Message-ID", "<gone@example.com>" ] ], server.searched
    assert_empty server.copied
    assert_empty server.stored
  end

  # --- Removing mail from a folder ----------------------------------------------
  # A plain EXPUNGE also removes messages that other mail clients flagged \Deleted.

  test "deleting a message removes only that message when the server supports UIDPLUS" do
    server = FakeImapServer.new(capabilities: %w[IMAP4REV1 UIDPLUS])

    connect_to_imap(server) { @service.delete_message(101, folder: "INBOX") }

    assert_equal [ [ 101, "+FLAGS", [ :Deleted ] ] ], server.stored
    assert_equal [ 101 ], server.expunged
  end

  test "deleting a message falls back to a plain expunge on servers without UIDPLUS" do
    server = FakeImapServer.new(capabilities: %w[IMAP4REV1])

    connect_to_imap(server) { @service.delete_message(101, folder: "INBOX") }

    assert_equal [ :all ], server.expunged
  end

  test "IMAP4rev2 servers remove only the deleted message too" do
    server = FakeImapServer.new(capabilities: %w[IMAP4REV2])

    connect_to_imap(server) { @service.delete_message(101, folder: "INBOX") }

    assert_equal [ 101 ], server.expunged
  end

  test "moving mail removes only the moved messages from the folder they leave" do
    server = FakeImapServer.new(folders: [ "INBOX", "Receipts", "Archive" ], message_ids: { [ "Archive", "<msg-006@example.com>" ] => [ 12, 13 ] })

    connect_to_imap(server) do
      @service.move_to_folder(101, source_folder: "INBOX", destination_folder: "Receipts")
      @service.move_to_folder_by_message_id("msg-006@example.com", source_folder: "Archive", destination_folder: "INBOX")
    end

    assert_equal [ 101, [ 12, 13 ] ], server.expunged
  end

  test "saving a draft again removes only its old copy" do
    draft = mails_messages(:draft_message)
    draft.update_column(:uid, 55)
    server = FakeImapServer.new(folders: [ "INBOX", "Drafts" ], message_ids: { [ "Drafts", draft.message_id ] => [ 56 ] })

    connect_to_imap(server) { @service.save_draft(draft) }

    assert_equal [ 55 ], server.expunged
    assert_equal [ [ "Drafts", [ :Draft, :Seen ] ] ], server.appended
    assert_equal 56, draft.reload.uid
  end

  # --- UTF-8 safety -----------------------------------------------------------
  # IMAP servers regularly return non-UTF-8 bytes; the service must not crash.

  test "safe_utf8 returns nil for nil" do
    assert_nil @service.send(:safe_utf8, nil)
  end

  test "safe_utf8 leaves valid UTF-8 unchanged" do
    assert_equal "héllo", @service.send(:safe_utf8, "héllo")
  end

  test "safe_utf8 replaces invalid bytes with the replacement character" do
    invalid = (+"héllo").force_encoding("ASCII-8BIT") + "\xC3".b
    result = @service.send(:safe_utf8, invalid)

    assert_equal Encoding::UTF_8, result.encoding
    assert_includes result, "�"
  end

  # --- Fetching and attachments -------------------------------------------------
  # Attachments come from the downloaded message itself. Some servers send
  # BODYSTRUCTUREs that net-imap can't parse, which failed the whole sync.

  test "fetches messages without asking for BODYSTRUCTURE" do
    imap = FakeImap.new(uids: [ 7 ], messages: [ fetch_data(7, report_mail.to_s) ])

    @service.send(:fetch_recent_emails, imap, "Projects", 50)

    assert_equal [ "UID", "ENVELOPE", "FLAGS", "INTERNALDATE", "BODY.PEEK[]" ], imap.fetched_attrs
    assert @account.messages.exists?(folder: "Projects", uid: 7)
  end

  test "saves attachments from the downloaded message, with decoded names" do
    @service.send(:save_email, fetch_data(9, report_mail.to_s), "INBOX")

    email = @account.messages.find_by!(message_id: "report-9@example.com")
    assert email.has_attachments
    attachment = email.attachments.sole
    assert_equal [ "café.pdf", "application/pdf", 16 ], [ attachment.filename, attachment.content_type, attachment.file_size ]
    assert_equal "%PDF-1.4 numbers", attachment.file.download
    assert_equal "See the numbers attached.", email.body_plain.strip
  end

  test "inline parts only count as attachments when they have a file name" do
    mail = Mail.new(from: "ann@example.com", to: "me@example.com", subject: "Pictures", message_id: "<pictures-3@example.com>")
    mail.html_part = Mail::Part.new(content_type: "text/html; charset=UTF-8", body: "<p>Look</p>")
    mail.add_part Mail::Part.new(content_type: "image/png", content_disposition: "inline", content_id: "<logo>", body: "PNG-unnamed")
    mail.add_part Mail::Part.new(content_type: "image/png", content_disposition: "inline; filename=photo.png", body: "PNG-named")

    @service.send(:save_email, fetch_data(3, mail.to_s), "INBOX")

    email = @account.messages.find_by!(message_id: "pictures-3@example.com")
    assert_equal [ "photo.png" ], email.attachments.map(&:filename)
  end

  test "an invitation sent inline, the way Outlook does, is found" do
    mail = Mail.new(from: "olivia@example.com", to: "me@example.com", subject: "Invitation: Budget review", message_id: "<outlook-invite@example.com>")
    mail.text_part = Mail::Part.new(content_type: "text/plain; charset=UTF-8", body: "You're invited")
    mail.add_part Mail::Part.new(content_type: "text/calendar; charset=UTF-8; method=REQUEST", body: <<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      METHOD:REQUEST
      BEGIN:VEVENT
      UID:outlook-1@example.com
      DTSTART:20261002T130000Z
      DTEND:20261002T140000Z
      SUMMARY:Budget review
      END:VEVENT
      END:VCALENDAR
    ICS

    @service.send(:save_email, fetch_data(4, mail.to_s), "INBOX")

    email = @account.messages.find_by!(message_id: "outlook-invite@example.com")
    assert_empty email.attachments
    assert_equal [ "outlook-1@example.com" ], email.calendar_invites.map(&:uid)
  end

  test "an attachment over the size limit is skipped, the email is still saved" do
    stub_const(ImapSyncService, :MAX_ATTACHMENT_SIZE, 10) do
      @service.send(:save_email, fetch_data(9, report_mail.to_s), "INBOX")
    end

    email = @account.messages.find_by!(message_id: "report-9@example.com")
    assert email.has_attachments
    assert_empty email.attachments
  end

  test "a server on a local address isn't contacted" do
    @account.update!(imap_host: "127.0.0.1")

    error = assert_raises(ImapSyncService::ConnectionError) { @service.sync_folders }
    assert_match "local address", error.message
  end

  test "a folder net-imap can't parse doesn't stop the sync" do
    @service.define_singleton_method(:connect) do
      raise Net::IMAP::ResponseParseError, "unexpected NIL (expected QUOTED or LITERAL)"
    end

    assert_nothing_raised { @service.sync_folder("Projects") }
  end

  private
    def special_folder(folder, folders)
      mailboxes = folders.map { |name, *attributes| Net::IMAP::MailboxList.new(attributes, "/", name) }
      @service.send(:find_special_folder, mailboxes, folder)
    end

    class FakeImap
      attr_reader :fetched_attrs

      def initialize(uids:, messages:)
        @uids = uids
        @messages = messages
      end

      def uid_search(_criteria) = @uids

      def uid_fetch(_uids, attrs)
        @fetched_attrs = attrs
        @messages
      end
    end

    def report_mail
      Mail.new do
        from "Ann <ann@example.com>"
        to "me@example.com"
        subject "Report"
        message_id "<report-9@example.com>"
        text_part { body "See the numbers attached." }
        add_file filename: "café.pdf", content: "%PDF-1.4 numbers"
      end
    end

    def fetch_data(uid, raw)
      message_id = Mail.new(raw).message_id
      envelope = Net::IMAP::Envelope.new(
        nil, "Test", [ Net::IMAP::Address.new("Ann", nil, "ann", "example.com") ], nil, nil,
        [ Net::IMAP::Address.new(nil, nil, "me", "example.com") ], nil, nil, nil, "<#{message_id}>"
      )
      Net::IMAP::FetchData.new(1, { "UID" => uid, "ENVELOPE" => envelope, "FLAGS" => [], "INTERNALDATE" => Time.current, "BODY[]" => raw })
    end

    def reconcile(folder, server_uids)
      @service.send(:reconcile_local_messages, folder, server_uids)
    end

    def reconcilable_inbox_ids
      @account.messages.where(folder: "INBOX", trashed: false, archived: false, draft: false).where.not(uid: nil)
    end
end

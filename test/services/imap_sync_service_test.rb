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

  test "find_sent_folder_from_list prefers plain Sent" do
    assert_equal "Sent",
      @service.send(:find_sent_folder_from_list, %w[INBOX Sent Trash])
  end

  test "find_sent_folder_from_list handles Gmail" do
    assert_equal "[Gmail]/Sent Mail",
      @service.send(:find_sent_folder_from_list, [ "INBOX", "[Gmail]/Sent Mail" ])
  end

  test "find_sent_folder_from_list handles cyrus-style INBOX.Sent" do
    assert_equal "INBOX.Sent",
      @service.send(:find_sent_folder_from_list, %w[INBOX INBOX.Sent INBOX.Trash])
  end

  test "find_sent_folder_from_list returns nil when no candidate" do
    assert_nil @service.send(:find_sent_folder_from_list, %w[INBOX Trash])
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

    error = assert_raises(ImapSyncService::ConnectionError) { @service.test_connection }
    assert_match "local address", error.message
  end

  test "a folder net-imap can't parse doesn't stop the sync" do
    @service.define_singleton_method(:connect) do
      raise Net::IMAP::ResponseParseError, "unexpected NIL (expected QUOTED or LITERAL)"
    end

    assert_nothing_raised { @service.sync_folder("Projects") }
  end

  private
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

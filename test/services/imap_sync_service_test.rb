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

  # --- RFC 2047 filename decoding ---------------------------------------------

  test "decode_filename returns plain ASCII filenames unchanged" do
    assert_equal "report.pdf", @service.send(:decode_filename, "report.pdf")
  end

  test "decode_filename decodes RFC 2047 Q-encoded filenames" do
    encoded = "=?UTF-8?Q?caf=C3=A9.pdf?="
    assert_equal "café.pdf", @service.send(:decode_filename, encoded)
  end

  test "decode_filename decodes RFC 2047 B-encoded filenames" do
    encoded = "=?UTF-8?B?Y2Fmw6kucGRm?=" # base64 of "café.pdf"
    assert_equal "café.pdf", @service.send(:decode_filename, encoded)
  end

  test "decode_filename returns nil for nil" do
    assert_nil @service.send(:decode_filename, nil)
  end

  private
    def reconcile(folder, server_uids)
      @service.send(:reconcile_local_messages, folder, server_uids)
    end

    def reconcilable_inbox_ids
      @account.messages.where(folder: "INBOX", trashed: false, archived: false, draft: false).where.not(uid: nil)
    end
end

# frozen_string_literal: true

require "net/imap"

class ImapSyncService
  class ConnectionError < StandardError; end
  class AuthenticationError < StandardError; end

  SPECIAL_FOLDERS = {
    "Sent" => [ :Sent, [ "Sent", "INBOX.Sent", "[Gmail]/Sent Mail", "Sent Messages", "Sent Items" ] ],
    "Drafts" => [ :Drafts, [ "Drafts", "INBOX.Drafts", "[Gmail]/Drafts", "Draft" ] ]
  }.freeze

  def initialize(email_account)
    @account = email_account
  end

  def sync_folders
    connect do |imap|
      mailboxes = imap.list("", "*") || []
      # The server's sent and drafts folders are known here as "Sent" and "Drafts"
      special = SPECIAL_FOLDERS.keys.index_by { |folder| find_special_folder(mailboxes, folder) }.except(nil)
      # Leave out Gmail's other system folders
      folders = mailboxes.map(&:name).reject { |f| f.start_with?("[Gmail]/") && !special.key?(f) }
      normalized = folders.map { |f| special.fetch(f, f) }.uniq
      @account.update!(synced_folders: normalized.to_json)
      normalized
    end
  end

  def sync_inbox(limit: 50)
    @account.mark_syncing!

    connect do |imap|
      imap.select("INBOX")
      fetch_recent_emails(imap, "INBOX", limit)
    end

    @account.mark_synced!
    true
  rescue StandardError => e
    @account.mark_sync_error!(e.message)
    raise
  end

  def sync_sent(limit: 50)
    connect do |imap|
      sent_folder = find_sent_folder(imap)
      return unless sent_folder

      imap.select(sent_folder)
      fetch_recent_emails(imap, "Sent", limit)
    end
  end

  def sync_folder(folder_name, limit: 50)
    connect do |imap|
      imap.select(folder_name)
      fetch_recent_emails(imap, folder_name, limit)
    end
  # A folder the server can't open, or whose messages net-imap can't parse, shouldn't stop the other folders from syncing
  rescue Net::IMAP::NoResponseError, Net::IMAP::ResponseParseError => e
    Rails.logger.warn("Could not sync folder #{folder_name}: #{e.class}: #{e.message}")
  end

  def mark_as_read(uid, folder: "INBOX")
    connect do |imap|
      select_folder(imap, folder)
      imap.uid_store(uid, "+FLAGS", [ :Seen ])
    end
  rescue StandardError => e
    Rails.logger.error("Failed to mark email as read on IMAP: #{e.message}")
  end

  def mark_as_unread(uid, folder: "INBOX")
    connect do |imap|
      select_folder(imap, folder)
      imap.uid_store(uid, "-FLAGS", [ :Seen ])
    end
  rescue StandardError => e
    Rails.logger.error("Failed to mark email as unread on IMAP: #{e.message}")
  end

  def set_starred(uid, starred, folder: "INBOX")
    connect do |imap|
      select_folder(imap, folder)
      if starred
        imap.uid_store(uid, "+FLAGS", [ :Flagged ])
      else
        imap.uid_store(uid, "-FLAGS", [ :Flagged ])
      end
    end
  rescue StandardError => e
    Rails.logger.error("Failed to update starred flag on IMAP: #{e.message}")
  end

  def create_folder(folder_name)
    connect { |imap| imap.create(folder_name) }
    sync_folders
  end

  def save_draft(message)
    raw = build_raw_email(message)

    connect do |imap|
      drafts_folder = find_special_folder(imap.list("", "*"), "Drafts")

      # Delete old draft from server if it exists
      if message.uid.present? && drafts_folder
        imap.select(drafts_folder)
        remove_from_folder(imap, message.uid)
      end

      # Upload new version
      if drafts_folder
        imap.append(drafts_folder, raw, [ :Draft, :Seen ])
        # Get the UID of the just-appended message
        imap.select(drafts_folder)
        uids = imap.uid_search([ "HEADER", "Message-ID", message.message_id ])
        message.update_column(:uid, uids.last) if uids.any?
      end
    end
  rescue StandardError => e
    Rails.logger.error("Failed to save draft to IMAP: #{e.message}")
  end

  def delete_draft(uid)
    return if uid.blank?

    delete_message(uid, folder: "Drafts")
  end

  # Takes one UID or several in the same folder
  def delete_message(uids, folder:)
    connect do |imap|
      select_folder(imap, folder)
      remove_from_folder(imap, uids)
    end
  rescue StandardError => e
    Rails.logger.error("Failed to delete email #{Array(uids).join(", ")} from #{folder}: #{e.message}")
  end

  def move_to_folder(uid, source_folder:, destination_folder:)
    connect do |imap|
      source, destination = server_folder_names(imap, source_folder, destination_folder)
      imap.select(source)
      imap.uid_copy(uid, destination)
      remove_from_folder(imap, uid)
    end
  rescue StandardError => e
    Rails.logger.error("Failed to move email #{uid} from #{source_folder} to #{destination_folder}: #{e.message}")
  end

  # A moved message gets a new UID in its new folder, so mail that was moved before, like
  # archived mail, is found by its Message-ID. The search matches parts of a header,
  # so it's done with the angle brackets: only this whole Message-ID matches.
  def move_to_folder_by_message_id(message_id, source_folder:, destination_folder:)
    connect do |imap|
      source, destination = server_folder_names(imap, source_folder, destination_folder)
      imap.select(source)
      uids = imap.uid_search([ "HEADER", "Message-ID", "<#{message_id.delete("<>")}>" ])
      next if uids.empty?

      imap.uid_copy(uids, destination)
      remove_from_folder(imap, uids)
    end
  rescue StandardError => e
    Rails.logger.error("Failed to move email #{message_id} from #{source_folder} to #{destination_folder}: #{e.message}")
  end

  private

  def incoming_message
    @incoming_message ||= ::Mails::IncomingMessage.new(@account)
  end

  def connect
    begin
      RemoteHost.verify!(@account.imap_host)
    rescue RemoteHost::Forbidden => e
      raise ConnectionError, e.message
    end

    ssl_options = if @account.imap_ssl
      {
        verify_mode: OpenSSL::SSL::VERIFY_PEER
      }
    else
      false
    end

    imap = Net::IMAP.new(
      @account.imap_host,
      port: @account.imap_port,
      ssl: ssl_options
    )

    begin
      begin
        imap.login(@account.username, @account.password)
      rescue Net::IMAP::NoResponseError
        raise AuthenticationError, Mails::Account::AUTHENTICATION_FAILED
      end
      yield imap
    ensure
      imap.logout rescue nil
      imap.disconnect rescue nil
    end
  end

  def fetch_recent_emails(imap, folder_name, limit)
    primary_folder = folder_name.in?(%w[INBOX Sent])

    if primary_folder
      all_server_uids = (imap.uid_search([ "ALL" ]) || []).sort
      reconcile_local_messages(folder_name, all_server_uids)

      existing_uids = @account.messages.where(folder: folder_name).where.not(uid: nil).pluck(:uid)
      new_uids = all_server_uids - existing_uids
      # Re-fetch the most recent existing messages too, so flag changes (read/starred) made in other clients get picked up.
      recent_existing = (all_server_uids & existing_uids).last(limit)
      uids = (new_uids + recent_existing).uniq.sort
    else
      since_date = 3.months.ago.strftime("%d-%b-%Y")
      uids = ((imap.uid_search([ "SINCE", since_date ]) || []).sort).last(limit)
    end
    return if uids.empty?

    # No BODYSTRUCTURE: attachments are read from the full message. Some servers send
    # BODYSTRUCTUREs with NIL where a string belongs, and net-imap then drops the connection.
    messages = imap.uid_fetch(uids, [ "UID", "ENVELOPE", "FLAGS", "INTERNALDATE", "BODY.PEEK[]" ])
    return unless messages

    messages.each do |msg|
      incoming_message.save(msg, folder_name)
    end
  end

  def reconcile_local_messages(folder_name, server_uids)
    # Remove local messages that no longer exist on the server in this folder.
    # Skip trashed/archived/draft rows — those are kept intentionally in other views.
    scope = @account.messages
      .where(folder: folder_name, trashed: false, archived: false, draft: false)
      .where.not(uid: nil)
    stale = server_uids.any? ? scope.where.not(uid: server_uids) : scope
    stale.destroy_all
  end

  # The email is already saved; a broken invite must not stop the rest of the batch from syncing.

  # Outlook sends invitations as an inline text/calendar part without a file name,
  # so they aren't saved as attachments

  # The parts a mail client lists as attachments: marked "attachment", or inline with a
  # file name (like pasted images). Parts without a disposition belong to the body.

  def find_sent_folder(imap)
    find_special_folder(imap.list("", "*"), "Sent")
  end

  def select_folder(imap, folder)
    imap.select(server_folder_names(imap, folder).first)
  end

  # A plain EXPUNGE removes every message flagged \Deleted in the folder, also ones another
  # mail client flagged without removing them. UID EXPUNGE removes only these messages.
  def remove_from_folder(imap, uids)
    imap.uid_store(uids, "+FLAGS", [ :Deleted ])

    if imap.capable?("UIDPLUS") || imap.capable?("IMAP4rev2")
      imap.uid_expunge(uids)
    else
      imap.expunge
    end
  end

  # Sent mail and drafts are kept in "Sent" and "Drafts" here, whatever the server calls
  # those folders ("[Gmail]/Sent Mail", "INBOX.Drafts", ...). Lists the server's folders at most once.
  def server_folder_names(imap, *folders)
    mailboxes = imap.list("", "*") if folders.intersect?(SPECIAL_FOLDERS.keys)
    folders.map { |folder| (mailboxes && find_special_folder(mailboxes, folder)) || folder }
  end

  # The folder the server marks with the SPECIAL-USE attribute (RFC 6154),
  # or else the first one with a name servers commonly use
  def find_special_folder(mailboxes, folder)
    attribute, names = SPECIAL_FOLDERS[folder]
    return unless attribute

    mailboxes.find { |mailbox| mailbox.attr.include?(attribute) }&.name ||
      names.find { |name| mailboxes.any? { |mailbox| mailbox.name == name } }
  end

  def build_raw_email(message)
    mail = Mail.new
    mail.message_id = message.message_id
    mail.from = message.from_address
    mail.to = JSON.parse(message.to_addresses || "[]")
    mail.cc = JSON.parse(message.cc_addresses || "[]") if message.cc_addresses.present?
    mail.subject = message.subject
    mail.date = message.sent_at || Time.current
    mail.in_reply_to = message.in_reply_to if message.in_reply_to.present?

    if message.body_html.present?
      mail.html_part = Mail::Part.new(content_type: "text/html; charset=UTF-8", body: message.body_html)
      mail.text_part = Mail::Part.new(content_type: "text/plain; charset=UTF-8", body: message.body_plain || "") if message.body_plain.present?
    else
      mail.body = message.body_plain || ""
      mail.content_type = "text/plain; charset=UTF-8"
    end

    mail.to_s
  end
end

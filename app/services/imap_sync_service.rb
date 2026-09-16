# frozen_string_literal: true

require "net/imap"

class ImapSyncService
  class ConnectionError < StandardError; end
  class AuthenticationError < StandardError; end

  MAX_ATTACHMENT_SIZE = 25.megabytes

  def initialize(email_account)
    @account = email_account
  end

  def test_connection
    connect do |imap|
      imap.list("", "*")
      true
    end
  rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
    raise AuthenticationError, "Authentication failed: #{e.message}"
  rescue StandardError => e
    raise ConnectionError, "Connection failed: #{e.message}"
  end

  def sync_folders
    connect do |imap|
      folders = imap.list("", "*")&.map(&:name) || []
      # Filter out Gmail system folders and NoSelect folders
      folders.reject! { |f| f.start_with?("[Gmail]/") && f != "[Gmail]/Sent Mail" }
      # Normalize: map provider-specific sent folders to "Sent"
      sent_folder = find_sent_folder_from_list(folders)
      normalized = folders.map do |f|
        f == sent_folder ? "Sent" : f
      end.uniq
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
      imap.select(folder)
      imap.uid_store(uid, "+FLAGS", [ :Seen ])
    end
  rescue StandardError => e
    Rails.logger.error("Failed to mark email as read on IMAP: #{e.message}")
  end

  def mark_as_unread(uid, folder: "INBOX")
    connect do |imap|
      imap.select(folder)
      imap.uid_store(uid, "-FLAGS", [ :Seen ])
    end
  rescue StandardError => e
    Rails.logger.error("Failed to mark email as unread on IMAP: #{e.message}")
  end

  def set_starred(uid, starred, folder: "INBOX")
    connect do |imap|
      imap.select(folder)
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
    drafts_folder = find_drafts_folder

    connect do |imap|
      # Delete old draft from server if it exists
      if message.uid.present? && drafts_folder
        imap.select(drafts_folder)
        imap.uid_store(message.uid, "+FLAGS", [ :Deleted ])
        imap.expunge
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
    drafts_folder = find_drafts_folder
    return unless drafts_folder && uid.present?

    delete_message(uid, folder: drafts_folder)
  rescue StandardError => e
    Rails.logger.error("Failed to delete draft from IMAP: #{e.message}")
  end

  def delete_message(uid, folder:)
    connect do |imap|
      imap.select(folder)
      imap.uid_store(uid, "+FLAGS", [ :Deleted ])
      imap.expunge
    end
  rescue StandardError => e
    Rails.logger.error("Failed to delete email #{uid} from #{folder}: #{e.message}")
  end

  def move_to_folder(uid, source_folder:, destination_folder:)
    connect do |imap|
      imap.select(source_folder)
      imap.uid_copy(uid, destination_folder)
      imap.uid_store(uid, "+FLAGS", [ :Deleted ])
      imap.expunge
    end
  rescue StandardError => e
    Rails.logger.error("Failed to move email #{uid} from #{source_folder} to #{destination_folder}: #{e.message}")
  end

  def fetch_email_body(uid, folder: "INBOX")
    connect do |imap|
      imap.select(folder)
      data = imap.fetch(uid, "BODY[]")&.first
      return nil unless data

      parse_email_body(data.attr["BODY[]"])
    end
  end

  private

  def connect
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
      imap.login(@account.username, @account.password)
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
      save_email(msg, folder_name)
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

  def save_email(msg, folder_name)
    envelope = msg.attr["ENVELOPE"]
    return unless envelope

    message_id = (envelope.message_id || "#{msg.attr['UID']}@#{@account.imap_host}").delete("<>")
    uid = msg.attr["UID"]
    flags = msg.attr["FLAGS"] || []

    from = envelope.from&.first
    from_address = from ? "#{from.mailbox}@#{from.host}" : nil
    from_name = decode_rfc2047(from&.name)

    to_list = (envelope.to || []).map { |addr| "#{addr.mailbox}@#{addr.host}" }
    cc_list = (envelope.cc || []).map { |addr| "#{addr.mailbox}@#{addr.host}" }

    sent_at = begin
      Time.parse(envelope.date.to_s)
    rescue
      msg.attr["INTERNALDATE"]
    end

    # Parse the full message with the mail gem to extract text/html parts
    raw_message = msg.attr["BODY[]"]
    parsed = parse_message_body(raw_message)

    # Extract threading headers from parsed message
    parsed_mail = parsed[:mail]
    in_reply_to = parsed_mail&.in_reply_to rescue nil
    references_val = parsed_mail&.references rescue nil
    references_str = Array(references_val).join(" ") if references_val

    attachment_parts = parsed_mail ? attachment_parts_of(parsed_mail) : []
    has_attachments = attachment_parts.any?

    email = @account.messages.find_or_initialize_by(message_id: message_id)
    is_new_email = email.new_record?

    email.assign_attributes(
      folder: folder_name,
      uid: uid,
      subject: decode_rfc2047(envelope.subject),
      from_address: from_address,
      from_name: from_name,
      to_addresses: to_list.to_json,
      cc_addresses: cc_list.to_json,
      body_plain: safe_utf8(parsed[:plain]),
      body_html: safe_utf8(parsed[:html]),
      read: flags.include?(:Seen),
      starred: flags.include?(:Flagged),
      sent_at: sent_at,
      in_reply_to: safe_utf8(in_reply_to),
      references: safe_utf8(references_str),
      has_attachments: has_attachments,
      thread_id: nil
    )
    email.save!

    # Save attachments for new emails, or existing ones missing attachments
    if has_attachments && (is_new_email || email.attachments.empty?)
      save_attachments(email, attachment_parts)
    end

    # Detect and create calendar invites for new emails
    detect_calendar_invite(email, calendar_data_of(parsed_mail)) if is_new_email
  end

  # The email is already saved; a broken invite must not stop the rest of the batch from syncing.
  def detect_calendar_invite(email, calendar_data = nil)
    MailInviteDetectorService.new(email, calendar_data: calendar_data).detect_and_create_invite
  rescue StandardError => e
    Rails.logger.error("Failed to detect calendar invite for email #{email.id}: #{e.class}: #{e.message}")
    nil
  end

  # Outlook sends invitations as an inline text/calendar part without a file name,
  # so they aren't saved as attachments
  def calendar_data_of(mail)
    return unless mail

    parts = mail.multipart? ? mail.all_parts : [ mail ]
    parts.find { |part| part.mime_type == "text/calendar" }&.decoded
  end

  def parse_message_body(raw_message)
    return { plain: nil, html: nil, mail: nil } if raw_message.blank?

    mail = Mail.read_from_string(raw_message)

    plain = if mail.multipart?
              mail.text_part&.decoded
    else
              mail.content_type&.start_with?("text/") ? mail.body.decoded : nil
    end

    html = if mail.multipart?
             mail.html_part&.decoded
    else
             mail.content_type&.start_with?("text/html") ? mail.body.decoded : nil
    end

    { plain: plain, html: html, mail: mail }
  rescue StandardError => e
    Rails.logger.warn("Failed to parse email body: #{e.message}")
    # Fall back to raw body
    { plain: raw_message, html: nil, mail: nil }
  end

  # The parts a mail client lists as attachments: marked "attachment", or inline with a
  # file name (like pasted images). Parts without a disposition belong to the body.
  def attachment_parts_of(mail)
    parts = mail.multipart? ? mail.all_parts : [ mail ]
    parts.select do |part|
      part.attachment? && part.header[:content_disposition]&.disposition_type.to_s.downcase.in?(%w[attachment inline])
    end
  end

  def save_attachments(email, parts)
    parts.each do |part|
      content = part.decoded
      next if content.bytesize > MAX_ATTACHMENT_SIZE

      filename = safe_utf8(part.filename)
      content_type = part.mime_type || "application/octet-stream"
      attachment = email.attachments.create!(filename: filename, content_type: content_type, file_size: content.bytesize)
      attachment.file.attach(io: StringIO.new(content), filename: filename, content_type: content_type)
    rescue StandardError => e
      Rails.logger.error("Failed to save attachment #{part.filename} for email #{email.id}: #{e.message}")
    end
  end

  def find_sent_folder(imap)
    folders = imap.list("", "*").map(&:name)
    find_sent_folder_from_list(folders)
  end

  def find_sent_folder_from_list(folders)
    sent_names = [ "Sent", "INBOX.Sent", "[Gmail]/Sent Mail", "Sent Messages", "Sent Items" ]
    sent_names.find { |name| folders.include?(name) }
  end

  def find_drafts_folder
    connect do |imap|
      folders = imap.list("", "*").map(&:name)
      drafts_names = [ "Drafts", "INBOX.Drafts", "[Gmail]/Drafts", "Draft" ]
      drafts_names.find { |name| folders.include?(name) }
    end
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

  def decode_rfc2047(str)
    return nil if str.nil?
    decoded = if str.match?(/=\?[^?]+\?[BQbq]\?[^?]+\?=/)
      Mail::Encodings.value_decode(str)
    else
      str
    end
    safe_utf8(decoded)
  rescue
    safe_utf8(str)
  end

  def safe_utf8(str)
    return nil if str.nil?
    str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "\uFFFD")
  end
end

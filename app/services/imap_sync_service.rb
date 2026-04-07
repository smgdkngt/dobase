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
  rescue Net::IMAP::NoResponseError => e
    Rails.logger.warn("Could not sync folder #{folder_name}: #{e.message}")
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
      # INBOX/Sent: fetch all messages (these folders are typically small)
      uids = imap.uid_search([ "ALL" ])
    else
      # Other folders: only fetch recent messages to avoid syncing huge history
      since_date = 3.months.ago.strftime("%d-%b-%Y")
      uids = imap.uid_search([ "SINCE", since_date ])
    end
    return if uids.empty?

    # Take the most recent UIDs (highest = newest)
    uids = uids.sort.last(limit)

    messages = imap.uid_fetch(uids, [ "UID", "ENVELOPE", "FLAGS", "INTERNALDATE", "BODY.PEEK[]", "BODYSTRUCTURE" ])
    return unless messages

    messages.each do |msg|
      save_email(imap, msg, folder_name)
    end
  end

  def save_email(imap, msg, folder_name)
    envelope = msg.attr["ENVELOPE"]
    return unless envelope

    message_id = (envelope.message_id || "#{msg.attr['UID']}@#{@account.imap_host}").delete("<>")
    uid = msg.attr["UID"]
    flags = msg.attr["FLAGS"] || []
    body_structure = msg.attr["BODYSTRUCTURE"]

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

    # Detect attachments from BODYSTRUCTURE
    attachment_parts = extract_attachment_parts(body_structure)
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

    # Download attachments for new emails, or existing ones missing attachments
    if has_attachments && (is_new_email || email.attachments.empty?)
      download_attachments(imap, uid, email, attachment_parts)
    end

    # Detect and create calendar invites for new emails
    if is_new_email
      MailInviteDetectorService.new(email).detect_and_create_invite
    end
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

  def extract_attachment_parts(body_structure, part_number = nil)
    attachments = []
    return attachments unless body_structure

    if body_structure.is_a?(Net::IMAP::BodyTypeMultipart)
      # Multipart message - iterate through parts
      body_structure.parts.each_with_index do |part, index|
        # Build the part number (1-indexed for IMAP)
        current_part = part_number ? "#{part_number}.#{index + 1}" : (index + 1).to_s
        attachments.concat(extract_attachment_parts(part, current_part))
      end
    elsif body_structure.is_a?(Net::IMAP::BodyTypeBasic) || body_structure.is_a?(Net::IMAP::BodyTypeText)
      # Single part - check if it's an attachment
      disposition = body_structure.disposition
      if attachment_disposition?(disposition) || inline_with_filename?(disposition)
        filename = extract_filename(body_structure)
        if filename.present?
          attachments << {
            part_number: part_number || "1",
            filename: filename,
            content_type: "#{body_structure.media_type}/#{body_structure.subtype}".downcase,
            size: body_structure.size || 0,
            encoding: body_structure.encoding
          }
        end
      end
    end

    attachments
  end

  def attachment_disposition?(disposition)
    return false unless disposition
    disposition.dsp_type&.downcase == "attachment"
  end

  def inline_with_filename?(disposition)
    return false unless disposition
    return false unless disposition.dsp_type&.downcase == "inline"
    disposition.param&.key?("FILENAME") || disposition.param&.key?("filename")
  end

  def extract_filename(body_structure)
    # Try disposition parameters first
    if body_structure.disposition&.param
      filename = body_structure.disposition.param["FILENAME"] ||
                 body_structure.disposition.param["filename"]
      return decode_filename(filename) if filename
    end

    # Fall back to body parameters
    if body_structure.param
      filename = body_structure.param["NAME"] || body_structure.param["name"]
      return decode_filename(filename) if filename
    end

    nil
  end

  def decode_filename(filename)
    return nil unless filename

    # Handle RFC 2047 encoded filenames
    if filename =~ /=\?([^?]+)\?([BQ])\?([^?]+)\?=/i
      charset, encoding, text = $1, $2, $3
      begin
        if encoding.upcase == "B"
          text = Base64.decode64(text)
        elsif encoding.upcase == "Q"
          text = text.gsub("_", " ").unpack1("M")
        end
        text.force_encoding(charset).encode("UTF-8")
      rescue
        filename
      end
    else
      filename
    end
  end

  def download_attachments(imap, uid, email, attachment_parts)
    attachment_parts.each do |part_info|
      next if part_info[:size] > MAX_ATTACHMENT_SIZE

      begin
        # Fetch the specific part
        fetch_key = "BODY.PEEK[#{part_info[:part_number]}]"
        data = imap.uid_fetch(uid, fetch_key)&.first
        next unless data

        raw_content = data.attr["BODY[#{part_info[:part_number]}]"]
        next unless raw_content

        # Decode the content based on encoding
        content = decode_attachment_content(raw_content, part_info[:encoding])
        next unless content

        # Create attachment record
        attachment = email.attachments.create!(
          filename: part_info[:filename],
          content_type: part_info[:content_type],
          file_size: content.bytesize
        )

        # Attach the file using Active Storage
        attachment.file.attach(
          io: StringIO.new(content),
          filename: part_info[:filename],
          content_type: part_info[:content_type]
        )
      rescue StandardError => e
        Rails.logger.error("Failed to download attachment #{part_info[:filename]} for email #{email.id}: #{e.message}")
      end
    end
  end

  def decode_attachment_content(raw_content, encoding)
    case encoding&.upcase
    when "BASE64"
      Base64.decode64(raw_content)
    when "QUOTED-PRINTABLE"
      raw_content.unpack1("M")
    when "7BIT", "8BIT", "BINARY", nil
      raw_content
    else
      raw_content
    end
  rescue StandardError => e
    Rails.logger.error("Failed to decode attachment content: #{e.message}")
    nil
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

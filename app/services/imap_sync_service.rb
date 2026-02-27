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
    # Get message count
    message_count = imap.status(imap.responses["EXISTS"]&.last || folder_name, [ "MESSAGES" ])["MESSAGES"] rescue imap.responses["EXISTS"]&.last || 0

    return if message_count.nil? || message_count == 0

    # Fetch the most recent emails - use BODY[] to get the full RFC822 message
    start_seq = [ message_count - limit + 1, 1 ].max
    range = start_seq..message_count

    messages = imap.fetch(range, [ "UID", "ENVELOPE", "FLAGS", "INTERNALDATE", "BODY.PEEK[]", "BODYSTRUCTURE" ])
    return unless messages

    messages.each do |msg|
      save_email(imap, msg, folder_name)
    end
  end

  def save_email(imap, msg, folder_name)
    envelope = msg.attr["ENVELOPE"]
    return unless envelope

    message_id = envelope.message_id || "#{msg.attr['UID']}@#{@account.imap_host}"
    uid = msg.attr["UID"]
    flags = msg.attr["FLAGS"] || []
    body_structure = msg.attr["BODYSTRUCTURE"]

    from = envelope.from&.first
    from_address = from ? "#{from.mailbox}@#{from.host}" : nil
    from_name = from&.name

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
      subject: envelope.subject,
      from_address: from_address,
      from_name: from_name,
      to_addresses: to_list.to_json,
      cc_addresses: cc_list.to_json,
      body_plain: parsed[:plain],
      body_html: parsed[:html],
      read: flags.include?(:Seen),
      starred: flags.include?(:Flagged),
      sent_at: sent_at,
      in_reply_to: in_reply_to,
      references: references_str,
      has_attachments: has_attachments
    )
    email.save!

    # Download and store attachments for new emails
    if is_new_email && has_attachments
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
        data = imap.fetch(uid, fetch_key)&.first
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
end

# frozen_string_literal: true

module Mails
  # Turns one message fetched over IMAP into the mail, attachments and calendar invite
  # Dobase stores for it.
  class IncomingMessage
    MAX_ATTACHMENT_SIZE = 25.megabytes
    # Shown where a byte is no letter in the mail's charset
    REPLACEMENT = "\uFFFD"
    # Charsets that mail with other letters in it names anyway
    UNSPECIFIC_CHARSET = /\A(us-ascii|utf-?8)\z/i

    def initialize(account)
      @account = account
    end

    # The message as fetched with ENVELOPE, FLAGS, INTERNALDATE and BODY[]
    def save(msg, folder_name)
      save_email(msg, folder_name)
    end

    # Attachments saved before their Content-IDs were kept get them from the message
    # as fetched again, matched on name and size
    def fill_in_content_ids(email, raw_message)
      remaining = email.attachments.where(content_id: nil).to_a
      attachment_parts_of(Mail.read_from_string(raw_message)).each do |part|
        content_id = content_id_of(part) or next
        attachment = remaining.find { |candidate| candidate.filename == safe_utf8(part.filename) && candidate.file_size == part.decoded.bytesize }
        next unless attachment

        attachment.update!(content_id: content_id)
        remaining.delete(attachment)
      end
    end

    private

    def save_email(msg, folder_name)
      envelope = msg.attr["ENVELOPE"]
      return unless envelope

      # A message without a Message-ID, or with an empty one ("<>"), is known by its UID
      message_id = envelope.message_id.to_s.delete("<>").strip.presence || "#{msg.attr['UID']}@#{@account.imap_host}"
      uid = msg.attr["UID"]
      flags = msg.attr["FLAGS"] || []

      from = envelope.from&.first
      from_address = from ? "#{from.mailbox}@#{from.host}" : nil
      from_name = unquote(decode_rfc2047(from&.name))

      to_list = addresses_of(envelope.to)
      cc_list = addresses_of(envelope.cc)

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
      # A reply to several messages names them all; the first one is the one it hangs under
      in_reply_to = Array(parsed_mail&.in_reply_to).first rescue nil
      references_val = parsed_mail&.references rescue nil
      references_str = Array(references_val).join(" ") if references_val

      attachment_parts = parsed_mail ? attachment_parts_of(parsed_mail) : []
      has_attachments = attachment_parts.any?

      # A message in several folders on the server has a copy here for each of them
      email = @account.messages.find_or_initialize_by(message_id: message_id, folder: folder_name)
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
      # Mail in the server's trash shows in the trash here
      email.trashed = true if folder_name == Account::TRASH
      email.save!

      # Save attachments for new emails, or existing ones missing attachments
      if has_attachments && (is_new_email || email.attachments.empty?)
        save_attachments(email, attachment_parts)
      end

      # Detect and create calendar invites for new emails
      detect_calendar_invite(email, calendar_data_of(parsed_mail)) if is_new_email
    end

    # A group among the recipients ("undisclosed-recipients:;") is listed as a start and an
    # end without a host, around its members: those two aren't addresses
    def addresses_of(list)
      (list || []).select { |addr| addr.mailbox.present? && addr.host.present? }.map { |addr| "#{addr.mailbox}@#{addr.host}" }
    end

    def detect_calendar_invite(email, calendar_data = nil)
      MailInviteDetectorService.new(email, calendar_data: calendar_data).detect_and_create_invite
    rescue StandardError => e
      Rails.logger.error("Failed to detect calendar invite for email #{email.id}: #{e.class}: #{e.message}")
      nil
    end

    def calendar_data_of(mail)
      return unless mail

      parts = mail.multipart? ? mail.all_parts : [ mail ]
      parts.find { |part| part.mime_type == "text/calendar" }&.decoded
    end

    def parse_message_body(raw_message)
      return { plain: nil, html: nil, mail: nil } if raw_message.blank?

      mail = Mail.read_from_string(raw_message)

      # A mail without a Content-Type is plain text (RFC 2045, 5.2)
      mime_type = mail.mime_type || "text/plain"

      plain = if mail.multipart?
                text_of(mail.text_part)
      else
                mime_type.start_with?("text/") && mime_type != "text/html" ? text_of(mail) : nil
      end

      html = if mail.multipart?
               text_of(mail.html_part)
      else
               mime_type == "text/html" ? text_of(mail) : nil
      end

      # A mail with only HTML gets its text for the list's preview and for search
      plain ||= PlainText.from_html(safe_utf8(html)) if html.present?

      { plain: plain, html: html, mail: mail }
    rescue StandardError => e
      Rails.logger.warn("Failed to parse email body: #{e.message}")
      # Fall back to raw body
      { plain: raw_message, html: nil, mail: nil }
    end

    # The text of a part, in the charset its Content-Type names. Text that names none, or one
    # its bytes don't fit ("us-ascii" above text with accents), is UTF-8 when it reads as
    # that. Text without a single UTF-8 letter in it is Windows-1252, which is what mail
    # programs that don't say send. Bytes that are no letter either way are replaced.
    def text_of(part)
      return unless part

      bytes = part.body.decoded
      charset = part.charset.presence if part.has_content_type?
      # A charset Ruby can't read these bytes in counts as none
      named = (Mail::Encodings.transcode_charset(bytes, charset) rescue nil) if charset
      return named if named && named.exclude?(REPLACEMENT)

      utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
      if utf8.valid_encoding?
        utf8
      elsif (charset.nil? || charset.match?(UNSPECIFIC_CHARSET)) && utf8.scrub("").ascii_only?
        bytes.dup.force_encoding(Encoding::WINDOWS_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT)
      else
        named || utf8.scrub(REPLACEMENT)
      end
    end

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
        attachment = email.attachments.create!(filename: filename, content_type: content_type, file_size: content.bytesize, content_id: content_id_of(part))
        attachment.file.attach(io: StringIO.new(content), filename: filename, content_type: content_type)
      rescue StandardError => e
        Rails.logger.error("Failed to save attachment #{part.filename} for email #{email.id}: #{e.message}")
      end
    end

    def content_id_of(part)
      safe_utf8(part.content_id)&.delete("<>").presence
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

    # Some servers hand over a name as it's written in the header, in quotes and with its
    # specials escaped: "Ann Example \(Acme\)" is Ann Example (Acme)
    def unquote(name)
      return name unless name&.match?(/\A\s*".*"\s*\z/m)
      name.strip[1..-2].gsub(/\\+(.)/m, '\1').strip
    end

    # Bytes without an encoding (net-imap hands some strings over that way) are read as UTF-8
    def safe_utf8(str)
      return nil if str.nil?
      str = str.dup.force_encoding(Encoding::UTF_8) if str.encoding == Encoding::BINARY
      return str.scrub(REPLACEMENT) if str.encoding == Encoding::UTF_8

      str.encode("UTF-8", invalid: :replace, undef: :replace, replace: REPLACEMENT)
    end
  end
end

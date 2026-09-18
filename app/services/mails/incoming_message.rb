# frozen_string_literal: true

module Mails
  # Turns one message fetched over IMAP into the mail, attachments and calendar invite
  # Dobase stores for it.
  class IncomingMessage
    MAX_ATTACHMENT_SIZE = 25.megabytes

    def initialize(account)
      @account = account
    end

    # The message as fetched with ENVELOPE, FLAGS, INTERNALDATE and BODY[]
    def save(msg, folder_name)
      save_email(msg, folder_name)
    end

    private

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
end

# frozen_string_literal: true

require "net/smtp"

class SmtpSendService
  class SendError < StandardError; end
  class ConnectionError < StandardError; end

  # Common MIME types for attachments
  MIME_TYPES = {
    # Documents
    ".pdf" => "application/pdf",
    ".doc" => "application/msword",
    ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls" => "application/vnd.ms-excel",
    ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".ppt" => "application/vnd.ms-powerpoint",
    ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".txt" => "text/plain",
    ".csv" => "text/csv",
    ".rtf" => "application/rtf",
    ".odt" => "application/vnd.oasis.opendocument.text",
    ".ods" => "application/vnd.oasis.opendocument.spreadsheet",
    # Images
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".bmp" => "image/bmp",
    ".webp" => "image/webp",
    ".svg" => "image/svg+xml",
    ".ico" => "image/x-icon",
    # Archives
    ".zip" => "application/zip",
    ".rar" => "application/vnd.rar",
    ".7z" => "application/x-7z-compressed",
    ".tar" => "application/x-tar",
    ".gz" => "application/gzip",
    # Audio/Video
    ".mp3" => "audio/mpeg",
    ".wav" => "audio/wav",
    ".mp4" => "video/mp4",
    ".avi" => "video/x-msvideo",
    ".mov" => "video/quicktime",
    # Code/Data
    ".json" => "application/json",
    ".xml" => "application/xml",
    ".html" => "text/html",
    ".css" => "text/css",
    ".js" => "application/javascript"
  }.freeze

  def initialize(email_account)
    @account = email_account
  end

  def test_connection
    smtp = build_smtp
    smtp.start(
      @account.smtp_host,
      @account.username,
      @account.password,
      @account.smtp_auth.to_sym
    )
    smtp.finish
    true
  rescue Net::SMTPAuthenticationError => e
    raise ConnectionError, "Authentication failed: #{e.message}"
  rescue StandardError => e
    raise ConnectionError, "Connection failed: #{e.message}"
  end

  # A reply passes the message_id of the message it answers as in_reply_to.
  def send_email(to:, subject:, body:, body_html: nil, cc: nil, bcc: nil, attachments: nil, in_reply_to: nil)
    in_reply_to = in_reply_to.presence
    email = { to: to, subject: subject, body: body, body_html: body_html, cc: cc, bcc: bcc, attachments: attachments,
              in_reply_to: in_reply_to, references: references_for(in_reply_to) }

    mail = deliver(**email)
    file_sent_email(mail, **email)

    true
  end

  private

  # The conversation up to the answered message, as far as it's known here, so mail
  # programs and the copy in Sent file the reply with it
  def references_for(in_reply_to)
    return unless in_reply_to

    @account.messages.find_by(message_id: in_reply_to)&.reply_references || in_reply_to
  end

  def deliver(**email)
    mail = build_mail(**email)

    smtp = build_smtp
    smtp.start(
      @account.smtp_host,
      @account.username,
      @account.password,
      @account.smtp_auth.to_sym
    ) do |server|
      # The addresses of To, Cc and Bcc, without the names the headers may give them
      server.send_message(mail.to_s, @account.email_address, mail.smtp_envelope_to)
    end

    mail
  rescue Net::SMTPError => e
    raise SendError, "Failed to send email: #{e.message}"
  rescue StandardError => e
    raise SendError, "Error: #{e.message}"
  end

  # The email has gone out by now. Failing to keep contacts or the sent copy is
  # reported, not raised: callers would otherwise think the send failed and try again.
  def file_sent_email(mail, **email)
    record_contacts(to: email[:to], cc: email[:cc], bcc: email[:bcc])
    save_sent_email(mail, **email)
  rescue StandardError => error
    Rails.error.report(error, context: { mail_account_id: @account.id, message_id: mail.message_id })
  end

  def build_smtp
    RemoteHost.verify!(@account.smtp_host)
    smtp = Net::SMTP.new(@account.smtp_host, @account.smtp_port)

    if @account.smtp_tls
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      smtp.enable_starttls_auto(ssl_context)
    end

    smtp
  end

  def build_mail(to:, subject:, body:, body_html:, cc:, bcc:, attachments:, in_reply_to:, references:)
    mail = Mail.new

    mail.from = @account.display_name.present? ? "#{@account.display_name} <#{@account.email_address}>" : @account.email_address
    mail.to = Array(to).join(", ")
    mail.cc = Array(cc).join(", ") if cc.present?
    mail.bcc = Array(bcc).join(", ") if bcc.present?
    mail.subject = subject
    mail.date = Time.current
    mail.message_id = "<#{SecureRandom.uuid}@#{@account.smtp_host}>"

    if in_reply_to
      mail.in_reply_to = in_reply_to
      mail.references = references
    end

    if body_html.present? && attachments.present?
      # The text and HTML are the message in two forms; attachments go next to them, not among them
      mail.part(content_type: "multipart/alternative") { |message| add_text_and_html(message, body, body_html) }
    elsif body_html.present? || attachments.present?
      add_text_and_html(mail, body, body_html)
    else
      mail.body = body
    end

    Array(attachments).each do |attachment|
      add_attachment(mail, attachment)
    end

    mail
  end

  def add_text_and_html(message, text, html)
    message.text_part = Mail::Part.new(body: text, content_type: "text/plain; charset=UTF-8")
    message.html_part = Mail::Part.new(body: html, content_type: "text/html; charset=UTF-8") if html.present?
  end

  def add_attachment(mail, attachment)
    filename, content, content_type = extract_attachment_data(attachment)
    return unless filename && content

    mail.add_file(
      filename: filename,
      content: content,
      content_type: content_type || mime_type_for(filename)
    )
  end

  def extract_attachment_data(attachment)
    case attachment
    when ActionDispatch::Http::UploadedFile
      # Uploaded file from form. Read twice: for the email and for the sent copy.
      attachment.rewind
      [
        attachment.original_filename,
        attachment.read,
        attachment.content_type
      ]
    when ActiveStorage::Blob
      # Active Storage blob
      [
        attachment.filename.to_s,
        attachment.download,
        attachment.content_type
      ]
    when ActiveStorage::Attached::One
      # Active Storage attached file
      return nil unless attachment.attached?
      blob = attachment.blob
      [
        blob.filename.to_s,
        blob.download,
        blob.content_type
      ]
    when Hash
      # Hash with :filename and :content keys (or :io for file-like objects)
      content = attachment[:content] || attachment[:io]&.read
      [
        attachment[:filename],
        content,
        attachment[:content_type]
      ]
    else
      # Try to handle file-like objects with read method
      if attachment.respond_to?(:read) && attachment.respond_to?(:original_filename)
        attachment.rewind if attachment.respond_to?(:rewind)
        [
          attachment.original_filename,
          attachment.read,
          attachment.respond_to?(:content_type) ? attachment.content_type : nil
        ]
      else
        nil
      end
    end
  end

  def mime_type_for(filename)
    extension = File.extname(filename).downcase
    MIME_TYPES[extension] || "application/octet-stream"
  end

  def record_contacts(to:, cc:, bcc:)
    all_recipients = Array(to) + Array(cc).compact + Array(bcc).compact

    all_recipients.each do |recipient|
      email, name = parse_email_address(recipient)
      next if email.blank?

      @account.record_contact(email, name)
    end
  end

  # "Ann Lee <ann@example.com>" is ["ann@example.com", "Ann Lee"], "ann@example.com" is ["ann@example.com", nil]
  def parse_email_address(address)
    parsed = Mail::Address.new(address.to_s.strip)
    [ parsed.address, parsed.display_name ]
  rescue Mail::Field::ParseError
    [ nil, nil ]
  end

  def save_sent_email(mail, subject:, body:, body_html:, attachments:, in_reply_to:, references:, **)
    email = @account.messages.create!(
      message_id: mail.message_id,
      in_reply_to: in_reply_to,
      references: references,
      folder: "Sent",
      subject: subject,
      from_address: @account.email_address,
      from_name: @account.display_name,
      # Addresses without names, like the mail that syncs in
      to_addresses: Array(mail.to).to_json,
      cc_addresses: Array(mail.cc).to_json,
      body_plain: body,
      body_html: body_html,
      read: true,
      has_attachments: Array(attachments).any?,
      sent_at: Time.current
    )

    # Save attachments to the email record if present
    save_attachments(email, attachments) if attachments.present?

    email
  end

  def save_attachments(email, attachments)
    Array(attachments).each do |attachment|
      filename, content, content_type = extract_attachment_data(attachment)
      next unless filename && content

      email_attachment = email.attachments.create!(
        filename: filename,
        content_type: content_type || mime_type_for(filename),
        file_size: content.bytesize
      )

      email_attachment.file.attach(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type || mime_type_for(filename)
      )
    end
  end
end

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

  def send_email(to:, subject:, body:, body_html: nil, cc: nil, bcc: nil, attachments: nil)
    mail = build_mail(to: to, subject: subject, body: body, body_html: body_html, cc: cc, bcc: bcc, attachments: attachments)

    smtp = build_smtp
    smtp.start(
      @account.smtp_host,
      @account.username,
      @account.password,
      @account.smtp_auth.to_sym
    ) do |server|
      recipients = Array(to) + Array(cc).compact + Array(bcc).compact
      server.send_message(mail.to_s, @account.email_address, recipients)
    end

    record_contacts(to: to, cc: cc, bcc: bcc)
    save_sent_email(mail, to: to, subject: subject, body: body, body_html: body_html, cc: cc, bcc: bcc, attachments: attachments)

    true
  rescue Net::SMTPError => e
    raise SendError, "Failed to send email: #{e.message}"
  rescue StandardError => e
    raise SendError, "Error: #{e.message}"
  end

  private

  def build_smtp
    smtp = Net::SMTP.new(@account.smtp_host, @account.smtp_port)

    if @account.smtp_tls
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      smtp.enable_starttls_auto(ssl_context)
    end

    smtp
  end

  def build_mail(to:, subject:, body:, body_html:, cc:, bcc:, attachments:)
    mail = Mail.new

    mail.from = @account.display_name.present? ? "#{@account.display_name} <#{@account.email_address}>" : @account.email_address
    mail.to = Array(to).join(", ")
    mail.cc = Array(cc).join(", ") if cc.present?
    mail.bcc = Array(bcc).join(", ") if bcc.present?
    mail.subject = subject
    mail.date = Time.current
    mail.message_id = "<#{SecureRandom.uuid}@#{@account.smtp_host}>"

    if body_html.present? || (attachments.present? && Array(attachments).any?)
      mail.text_part = Mail::Part.new do
        body body
        content_type "text/plain; charset=UTF-8"
      end

      if body_html.present?
        mail.html_part = Mail::Part.new do
          body body_html
          content_type "text/html; charset=UTF-8"
        end
      end

      Array(attachments).each do |attachment|
        add_attachment(mail, attachment)
      end
    else
      mail.body = body
    end

    mail
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
    when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile
      # Uploaded file from form
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

  def parse_email_address(address)
    return [ nil, nil ] if address.blank?

    address = address.to_s.strip

    # Handle "Name <email@example.com>" format
    if address =~ /\A(.+?)\s*<(.+?)>\z/
      name = Regexp.last_match(1).strip.gsub(/\A["']|["']\z/, "")
      email = Regexp.last_match(2).strip
      [ email, name ]
    else
      # Just an email address
      [ address, nil ]
    end
  end

  def save_sent_email(mail, to:, subject:, body:, body_html:, cc:, bcc:, attachments:)
    email = @account.emails.create!(
      message_id: mail.message_id,
      folder: "Sent",
      subject: subject,
      from_address: @account.email_address,
      from_name: @account.display_name,
      to_addresses: Array(to).to_json,
      cc_addresses: Array(cc).compact.to_json,
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

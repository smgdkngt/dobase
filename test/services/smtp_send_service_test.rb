# frozen_string_literal: true

require "test_helper"

class SmtpSendServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = mails_accounts(:primary)
    @service = SmtpSendService.new(@account)

    smtp = @smtp = SmtpTestHelper::FakeSmtp.new
    @service.define_singleton_method(:build_smtp) { smtp }
  end

  test "STARTTLS checks the server's certificate against the system's authorities and its host name" do
    smtp = SmtpSendService.new(@account).send(:build_smtp)
    context = smtp.instance_variable_get(:@ssl_context_starttls)

    assert smtp.starttls_auto?
    assert_equal OpenSSL::SSL::VERIFY_PEER, context.verify_mode
    assert context.verify_hostname
    assert_not_nil context.cert_store
  end

  test "the HTML part carries the editor's spacing inline, the text part has its paragraphs" do
    @service.send_email(to: [ "friend@example.com" ], subject: "Plans", body: "Hi\n\nThursday", body_html: "<p>Hi</p><p>Thursday</p>")

    mail = Mail.new(@smtp.deliveries.sole[:message])
    assert_includes mail.html_part.decoded, '<p style="margin:0 0 1em 0">Hi</p><p style="margin:0 0 1em 0">Thursday</p>'
    assert_equal "Hi\n\nThursday", mail.text_part.decoded
    assert_equal "<p>Hi</p><p>Thursday</p>", @account.messages.find_by!(subject: "Plans").body_html
  end

  test "sending delivers the email and keeps a copy in Sent" do
    assert_difference -> { @account.messages.sent.count }, 1 do
      @service.send_email(to: [ "friend@example.com" ], cc: [ "colleague@example.com" ], subject: "Hello",
        body: "Hi there", body_html: "<p>Hi there</p>")
    end

    delivery = @smtp.deliveries.sole
    assert_equal "testuser@example.com", delivery[:from]
    assert_equal [ "friend@example.com", "colleague@example.com" ], delivery[:recipients]
    assert_no_match(/^(In-Reply-To|References):/, delivery[:message])

    sent = @account.messages.find_by!(subject: "Hello")
    assert_equal "Sent", sent.folder
    assert_equal [ "friend@example.com" ], sent.to_addresses_list
    assert_equal [ "colleague@example.com" ], sent.cc_addresses_list
    assert_equal "<p>Hi there</p>", sent.body_html
    assert_equal [ "colleague@example.com", "friend@example.com" ], @account.contacts.pluck(:email_address).sort
  end

  test "sending asks for a sync, which puts a copy in the server's sent folder" do
    assert_enqueued_with(job: SyncEmailsJob, args: [ @account.id ]) do
      @service.send_email(to: [ "friend@example.com" ], subject: "Hello", body: "Hi")
    end
  end

  test "recipients keep their names in the headers, and only their addresses go to the mail server" do
    @service.send_email(to: [ "Friendly Sender <sender@example.com>" ], cc: [ "Reports Bot <reports@example.com>" ],
      bcc: [ "Archive <archive@example.com>" ], subject: "Hello", body: "Hi")

    delivery = @smtp.deliveries.sole
    assert_equal [ "sender@example.com", "reports@example.com", "archive@example.com" ], delivery[:recipients]
    assert_match "To: Friendly Sender <sender@example.com>", delivery[:message]
    assert_match "Cc: Reports Bot <reports@example.com>", delivery[:message]
    assert_no_match "archive@example.com", delivery[:message]

    sent = @account.messages.find_by!(subject: "Hello")
    assert_equal [ "sender@example.com" ], sent.to_addresses_list
    assert_equal [ "reports@example.com" ], sent.cc_addresses_list
    assert_equal "Friendly Sender", @account.contacts.find_by!(email_address: "sender@example.com").name
  end

  test "a reply names the message it answers and that message's ancestors, and joins its conversation" do
    parent = mails_messages(:inbox_read)
    parent.update!(in_reply_to: "<msg-000@example.com>")

    @service.send_email(to: [ "reports@example.com" ], subject: "Re: Your weekly report", body: "Thanks", in_reply_to: parent.message_id)

    message = @smtp.deliveries.sole[:message]
    assert_match "In-Reply-To: <msg-002@example.com>", message
    assert_match(/References: <msg-000@example.com>\s+<msg-002@example.com>/, message)

    reply = @account.messages.sent.find_by!(subject: "Re: Your weekly report")
    assert_equal [ parent.message_id, "<msg-000@example.com> <msg-002@example.com>" ], [ reply.in_reply_to, reply.references ]
    assert_equal parent.thread_id, reply.thread_id
  end

  test "a reply to a message that isn't here still names it" do
    @service.send_email(to: [ "friend@example.com" ], subject: "Re: Plans", body: "Yes", in_reply_to: "plans@example.com")

    message = @smtp.deliveries.sole[:message]
    assert_match "In-Reply-To: <plans@example.com>", message
    assert_match "References: <plans@example.com>", message

    reply = @account.messages.sent.find_by!(subject: "Re: Plans")
    assert_equal [ "plans@example.com" ] * 3, [ reply.in_reply_to, reply.references, reply.thread_id ]
  end

  test "a failure after delivery is reported, not raised as a failed send" do
    @service.define_singleton_method(:save_sent_email) { |*| raise ActiveRecord::StatementInvalid, "database is locked" }
    reported = []
    subscriber = Object.new
    subscriber.define_singleton_method(:report) { |error, **| reported << error }
    Rails.error.subscribe(subscriber)

    assert @service.send_email(to: [ "friend@example.com" ], subject: "Hello", body: "Hi")
    assert_equal 1, @smtp.deliveries.size
    assert_equal [ "database is locked" ], reported.map(&:message)
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  test "forwarded attachments from storage go out with the email" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1"), filename: "report.pdf", content_type: "application/pdf")

    @service.send_email(to: [ "friend@example.com" ], subject: "Fwd: report", body: "See attached", attachments: [ blob ])

    assert_includes @smtp.deliveries.sole[:message], "report.pdf"
  end

  test "uploaded attachments go out with the email and stay with the sent copy" do
    file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "notes.txt")

    @service.send_email(to: [ "friend@example.com" ], subject: "Notes", body: "Attached", attachments: [ file ])

    assert_includes @smtp.deliveries.sole[:message], "notes.txt"
    attachment = @account.messages.find_by!(subject: "Notes").attachments.sole
    assert_equal "notes.txt", attachment.filename
    assert_equal 5, attachment.file_size
    assert_equal "hello", attachment.file.download
  end

  test "attachments go next to the text and HTML of the email, not among them" do
    file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "notes.txt")

    @service.send_email(to: [ "friend@example.com" ], subject: "Notes", body: "Attached", body_html: "<p>Attached</p>", attachments: [ file ])

    mail = Mail.new(@smtp.deliveries.sole[:message])
    assert_equal "multipart/mixed", mail.mime_type
    assert_equal [ "multipart/alternative", "text/plain" ], mail.parts.map(&:mime_type)
    assert_equal [ "text/plain", "text/html" ], mail.parts.first.parts.map(&:mime_type)
    assert_equal [ "notes.txt" ], mail.attachments.map(&:filename)
    assert_equal [ "Attached", %(<p style="margin:0 0 1em 0">Attached</p>) ], [ mail.text_part.decoded, mail.html_part.decoded ]
  end

  test "an email without attachments has its text and HTML as alternatives" do
    @service.send_email(to: [ "friend@example.com" ], subject: "Hello", body: "Hi", body_html: "<p>Hi</p>")

    mail = Mail.new(@smtp.deliveries.sole[:message])
    assert_equal "multipart/alternative", mail.mime_type
    assert_equal [ "text/plain", "text/html" ], mail.parts.map(&:mime_type)
  end
  test "a mail server on a private network isn't contacted" do
    @account.update!(smtp_host: "mail.internal")

    error = assert_raises(SmtpSendService::SendError) do
      SmtpSendService.new(@account).send_email(to: "ann@example.com", subject: "Hi", body: "Hello")
    end
    assert_match "private network", error.message
  end

  test "a mail server that can't be reached is told apart, since nothing went out" do
    @smtp.define_singleton_method(:start) { |*| raise Errno::ECONNREFUSED }

    error = assert_raises(SmtpSendService::Unreachable) do
      @service.send_email(to: "ann@example.com", subject: "Hi", body: "Hello")
    end
    assert_equal "Couldn't reach #{@account.smtp_host}: Connection refused", error.message
  end

  test "a connection lost after the mail server was reached isn't, since the mail may have gone out" do
    @smtp.define_singleton_method(:send_message) { |*| raise Errno::ETIMEDOUT }

    error = assert_raises(SmtpSendService::SendError) do
      @service.send_email(to: "ann@example.com", subject: "Hi", body: "Hello")
    end
    assert_not_kind_of SmtpSendService::Unreachable, error
  end
end

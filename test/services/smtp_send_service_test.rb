# frozen_string_literal: true

require "test_helper"

class SmtpSendServiceTest < ActiveSupport::TestCase
  # Records what would have gone over SMTP, so no test talks to a mail server.
  class FakeSmtp
    attr_reader :deliveries

    def initialize
      @deliveries = []
    end

    def start(*)
      yield self
    end

    def send_message(message, from, recipients)
      @deliveries << { message: message, from: from, recipients: recipients }
    end
  end

  setup do
    @account = mails_accounts(:primary)
    @service = SmtpSendService.new(@account)

    smtp = @smtp = FakeSmtp.new
    @service.define_singleton_method(:build_smtp) { smtp }
  end

  test "sending delivers the email and keeps a copy in Sent" do
    assert_difference -> { @account.messages.sent.count }, 1 do
      @service.send_email(to: [ "friend@example.com" ], cc: [ "colleague@example.com" ], subject: "Hello",
        body: "Hi there", body_html: "<p>Hi there</p>")
    end

    delivery = @smtp.deliveries.sole
    assert_equal "testuser@example.com", delivery[:from]
    assert_equal [ "friend@example.com", "colleague@example.com" ], delivery[:recipients]

    sent = @account.messages.find_by!(subject: "Hello")
    assert_equal "Sent", sent.folder
    assert_equal [ "friend@example.com" ], sent.to_addresses_list
    assert_equal [ "colleague@example.com" ], sent.cc_addresses_list
    assert_equal "<p>Hi there</p>", sent.body_html
    assert_equal [ "colleague@example.com", "friend@example.com" ], @account.contacts.pluck(:email_address).sort
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
  test "a mail server on a private network isn't contacted" do
    @account.update!(smtp_host: "mail.internal")

    error = assert_raises(SmtpSendService::SendError) do
      SmtpSendService.new(@account).send_email(to: "ann@example.com", subject: "Hi", body: "Hello")
    end
    assert_match "private network", error.message
  end
end

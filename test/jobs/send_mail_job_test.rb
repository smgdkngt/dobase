# frozen_string_literal: true

require "test_helper"

class SendMailJobTest < ActiveJob::TestCase
  setup do
    @draft = mails_messages(:draft_message)
    @sender = users(:one)
  end

  test "mail is tried again while the mail server can't be reached, and sent when it can" do
    attempts = 0
    deliveries = assert_no_difference(-> { @sender.notifications.count }) do
      with_mail_server(-> { attempts += 1; attempts < 3 }) do
        perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) }
      end
    end

    assert_equal 3, attempts
    assert_equal [ "recipient@example.com" ], deliveries.sole[:recipients]
    assert_not Mails::Message.exists?(@draft.id)
  end

  test "mail stays a draft and the sender hears why when the mail server stays out of reach" do
    attempts = 0
    with_mail_server(-> { attempts += 1 }) do
      perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) }
    end

    assert_equal 5, attempts
    assert Mails::Message.exists?(@draft.id)
    assert_enqueued_with(job: SyncDraftJob, args: [ @draft.id ])
    notification = @sender.notifications.order(:created_at).last
    assert_equal "Couldn't send “Draft email”, it's in your drafts: " \
                 "Couldn't reach #{@draft.account.smtp_host}: getaddrinfo: Temporary failure in name resolution",
                 notification.message
  end

  test "mail the mail server turned down isn't tried again" do
    attempts = 0
    smtp = SmtpTestHelper::FakeSmtp.new
    smtp.define_singleton_method(:send_message) { |*| attempts += 1; raise Net::SMTPFatalError, "550 No such user" }
    with_smtp(smtp) do
      perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) }
    end

    assert_equal 1, attempts
    assert Mails::Message.exists?(@draft.id)
    assert_match "550 No such user", @sender.notifications.order(:created_at).last.message
  end

  private

  # A mail server whose name can't be looked up while unreachable returns true
  def with_mail_server(unreachable)
    smtp = SmtpTestHelper::FakeSmtp.new
    start = smtp.method(:start)
    smtp.define_singleton_method(:start) do |*args, &block|
      raise SocketError, "getaddrinfo: Temporary failure in name resolution" if unreachable.call
      start.call(*args, &block)
    end
    with_smtp(smtp) { yield }
    smtp.deliveries
  end

  def with_smtp(smtp)
    SmtpSendService.singleton_class.define_method(:new) do |*args|
      super(*args).tap { |service| service.define_singleton_method(:build_smtp) { smtp } }
    end
    yield
  ensure
    SmtpSendService.singleton_class.remove_method(:new)
  end
end

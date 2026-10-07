# frozen_string_literal: true

require "test_helper"

class SendMailJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @draft = mails_messages(:draft_message)
    @sender = users(:one)
  end

  test "every window that shows the mailbox hears that the mail has gone out" do
    assert_broadcast_on(PresenceChannel.broadcasting_for(@draft.account.tool), type: "changed", tool_id: @draft.account.tool.id) do
      with_mail_server(-> { false }) do
        perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) }
      end
    end
    assert_equal [ "Sent", false, false ], @draft.reload.values_at(:folder, :draft, :sending)
  end

  test "and that it is a draft again when the mail server turned it down" do
    smtp = SmtpTestHelper::FakeSmtp.new
    smtp.define_singleton_method(:send_message) { |*| raise Net::SMTPFatalError, "550 No such user" }

    assert_broadcasts(PresenceChannel.broadcasting_for(@draft.account.tool), 1) do
      with_smtp(smtp) { perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) } }
    end
    assert_equal [ "Drafts", true, false ], @draft.reload.values_at(:folder, :draft, :sending)
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
    assert_equal [ "Sent", false, false ], @draft.reload.values_at(:folder, :draft, :sending)
  end

  test "mail is in Sent, marked as being sent, while the mail server can't be reached" do
    states = []
    with_mail_server(-> { states << @draft.reload.values_at(:folder, :draft, :sending); states.size < 2 }) do
      perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) }
    end

    assert_equal [ [ "Sent", false, true ] ] * 2, states
  end

  test "mail is a draft again and the sender hears why when the mail server stays out of reach" do
    attempts = 0
    with_mail_server(-> { attempts += 1 }) do
      perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) }
    end

    assert_equal 5, attempts
    assert_equal [ "Drafts", true, false ], @draft.reload.values_at(:folder, :draft, :sending)
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
    assert_equal [ "Drafts", true, false ], @draft.reload.values_at(:folder, :draft, :sending)
    assert_match "550 No such user", @sender.notifications.order(:created_at).last.message
  end

  test "mail that can't be put together is a draft again, the sender hears why, and the error is reported" do
    original = mails_messages(:inbox_read)
    original.update!(body_html: %(<p>Lunch?</p><img src="cid:logo@example.com">))
    logo = original.attachments.create!(filename: "logo.png", content_type: "image/png", file_size: 3, content_id: "logo@example.com")
    logo.file.attach(io: StringIO.new("PNG"), filename: "logo.png", content_type: "image/png")
    logo.file.blob.service.delete(logo.file.blob.key)
    @draft.update!(quoted_message: original, in_reply_to: original.message_id)
    smtp = SmtpTestHelper::FakeSmtp.new

    report = assert_error_reported(ActiveStorage::FileNotFoundError) do
      with_smtp(smtp) { perform_enqueued_jobs(only: SendMailJob) { SendMailJob.perform_later(@draft, @sender) } }
    end

    assert_empty smtp.deliveries
    assert_equal [ "Drafts", true, false ], @draft.reload.values_at(:folder, :draft, :sending)
    assert_equal({ mail_account_id: @draft.mail_account_id, mail_message_id: @draft.id }, report.context.slice(:mail_account_id, :mail_message_id))
    assert_enqueued_with(job: SyncDraftJob, args: [ @draft.id ])
    assert_equal "Couldn't send “Draft email”, it's in your drafts: Something went wrong before it reached the mail server",
      @sender.notifications.order(:created_at).last.message
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

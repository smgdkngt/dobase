# frozen_string_literal: true

# Sends mail written on the compose page. It's in Sent already, marked as being sent, so it
# shows in its conversation and has left Drafts. Not sent, it's a draft again and the sender
# hears why. It's only tried again when the mail server couldn't be reached, for a few
# minutes: a mail server that failed halfway may have sent it anyway.
class SendMailJob < ApplicationJob
  queue_as :default
  skip_in_demo
  # Thrown away before it went out
  discard_on ActiveJob::DeserializationError
  retry_on SmtpSendService::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send(:not_sent, *job.arguments, error)
  end

  def perform(message, sender)
    message.start_sending! if message.draft?

    body_html = message.outgoing_html
    SmtpSendService.new(message.account).send_email(
      to: message.to_addresses_list, cc: message.cc_addresses_list.presence, bcc: message.bcc_addresses_list.presence,
      subject: message.subject, body: Mails::PlainText.from_html(body_html), body_html: body_html,
      attachments: message.attachments.filter_map { |attachment| attachment.file.blob if attachment.file.attached? }.presence,
      inline_images: Mails::Quote.of(message)&.inline_images.presence, in_reply_to: message.in_reply_to,
      sent_copy: message
    )

    # It has gone out, whatever became of filing it
    Mails::Message.where(id: message.id).update_all(sending: false)
  rescue SmtpSendService::Unreachable
    raise
  rescue SmtpSendService::SendError => error
    not_sent(message, sender, error)
  end

  private

  def not_sent(message, sender, error)
    message.back_to_drafts!
    # Saved to the server's Drafts folder too, like any draft
    SyncDraftJob.perform_later(message.id)
    MailNotSentNotifier.with(draft: message, error: error.message, tool: message.account.tool).deliver(sender)
  end
end

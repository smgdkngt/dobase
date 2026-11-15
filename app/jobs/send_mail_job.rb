# frozen_string_literal: true

# Sends mail written on the compose page. It's in Sent already, marked as being sent, so it
# shows in its conversation and has left Drafts. Not sent, it's a draft again and the sender
# hears why. It's only tried again when the mail server couldn't be reached, for a few
# minutes: a mail server that failed halfway may have sent it anyway. Anything else that
# goes wrong does so before the mail server gets the mail, and is reported.
class SendMailJob < ApplicationJob
  queue_as :default
  # How long Send can be undone
  UNDO_TIME = 10.seconds
  skip_in_demo
  # Thrown away before it went out
  discard_on ActiveJob::DeserializationError
  retry_on SmtpSendService::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send(:not_sent, *job.arguments.first(2), error.message)
  end

  # sending: the Message-ID the mail was given when it was sent off (Mails::Message#start_sending!),
  # which it gets anew every time. Taken back and sent again, it's the second send's job that
  # sends it, not this one, which would send it before its own moment to undo is over.
  def perform(message, sender, sending: nil)
    # Sent off from the compose page, it waits a moment, in which Send can be undone
    # (Mails::Message#take_back!). Taken back, it's a draft again and isn't sent. Once it
    # is taken here it can't be taken back; a try again after the mail server couldn't be
    # reached has it already.
    return unless executions > 1 ? message.reload.sending? : message.claim_for_sending!(sending)

    begin

      body_html = message.outgoing_html
      SmtpSendService.new(message.account).send_email(
        to: message.to_addresses_list, cc: message.cc_addresses_list.presence, bcc: message.bcc_addresses_list.presence,
        subject: message.subject, body: Mails::PlainText.from_html(body_html, links: true), body_html: body_html,
        attachments: message.attachments.filter_map { |attachment| attachment.file.blob if attachment.file.attached? }.presence,
        inline_images: Mails::Quote.of(message)&.inline_images.presence, in_reply_to: message.in_reply_to,
        sent_copy: message, quoted: message.quoted_message, sender: sender
      )
    rescue SmtpSendService::Unreachable
      raise
    rescue SmtpSendService::SendError => error
      return not_sent(message, sender, error.message)
    rescue StandardError => error
      # Left as it is, it would say "Sending…" in Sent forever
      Rails.error.report(error, context: { mail_account_id: message.mail_account_id, mail_message_id: message.id })
      return not_sent(message, sender, "Something went wrong before it reached the mail server")
    end

    # It has gone out, whatever became of filing it
    Mails::Message.where(id: message.id).update_all(sending: false)
    # No longer "Sending…" in any window that shows the mailbox (Tool#announce_change)
    message.account.tool.announce_change
  end

  private

  def not_sent(message, sender, reason)
    message.back_to_drafts!
    message.account.tool.announce_change
    # Saved to the server's Drafts folder too, like any draft
    SyncDraftJob.perform_later(message.id)
    MailNotSentNotifier.with(draft: message, error: reason, tool: message.account.tool).deliver(sender)
  end
end

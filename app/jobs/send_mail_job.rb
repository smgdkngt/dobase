# frozen_string_literal: true

# Sends a draft written on the compose page. Sent, the draft is gone and the mail is in Sent;
# not sent, the draft stays and the sender hears why. It's only tried again when the mail
# server couldn't be reached, for a few minutes: a mail server that failed halfway may have
# sent it anyway.
class SendMailJob < ApplicationJob
  queue_as :default
  skip_in_demo
  # Thrown away before it went out
  discard_on ActiveJob::DeserializationError
  retry_on SmtpSendService::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send(:not_sent, *job.arguments, error)
  end

  def perform(draft, sender)
    account = draft.account

    body_html = draft.outgoing_html
    SmtpSendService.new(account).send_email(
      to: draft.to_addresses_list, cc: draft.cc_addresses_list.presence, bcc: draft.bcc_addresses_list.presence,
      subject: draft.subject, body: Mails::PlainText.from_html(body_html), body_html: body_html,
      attachments: draft.attachments.filter_map { |attachment| attachment.file.blob if attachment.file.attached? }.presence,
      inline_images: Mails::Quote.of(draft)&.inline_images.presence, in_reply_to: draft.in_reply_to
    )

    ImapSyncJob.perform_later(account.id, "delete_draft", draft.uid, "Drafts") if draft.uid
    draft.destroy
  rescue SmtpSendService::Unreachable
    raise
  rescue SmtpSendService::SendError => error
    not_sent(draft, sender, error)
  end

  private

  def not_sent(draft, sender, error)
    # Saved to the server's Drafts folder too, like any draft
    SyncDraftJob.perform_later(draft.id)
    MailNotSentNotifier.with(draft: draft, error: error.message, tool: draft.account.tool).deliver(sender)
  end
end

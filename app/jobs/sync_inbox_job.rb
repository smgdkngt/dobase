# frozen_string_literal: true

class SyncInboxJob < ApplicationJob
  queue_as :default
  skip_in_demo

  limits_concurrency key: ->(mail_account_id) { mail_account_id }, group: SyncEmailsJob::GROUP, duration: 15.minutes

  def perform(mail_account_id)
    mail_account = Mails::Account.find_by(id: mail_account_id)
    return if mail_account.nil? || mail_account.waiting_after_refused_login?

    before = SyncEmailsJob.shown(mail_account)
    service = ::ImapSyncService.new(mail_account)
    service.sync_inbox(limit: 50)
    mail_account.broadcast_unread_mail
  rescue ::ImapSyncService::ConnectionError, ::ImapSyncService::AuthenticationError, *::ImapSyncService::UNREACHABLE => e
    Rails.logger.error("Inbox sync failed for account #{mail_account_id}: #{e.message}")
    mail_account.mark_sync_error!(e.message)
  ensure
    service&.record_events(complete: false)
    mail_account.tool.announce_change if before && SyncEmailsJob.shown(mail_account) != before
  end
end

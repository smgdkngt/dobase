# frozen_string_literal: true

class SyncEmailsJob < ApplicationJob
  queue_as :default

  # The mail page asks for a sync every minute in every open tab. One sync per account at a time is enough.
  limits_concurrency key: ->(mail_account_id) { mail_account_id }, duration: 15.minutes, on_conflict: :discard

  def perform(mail_account_id)
    mail_account = Mails::Account.find_by(id: mail_account_id)
    return if mail_account.nil? || mail_account.authentication_failed?

    service = ::ImapSyncService.new(mail_account)
    service.sync_folders
    service.sync_inbox(limit: 50)
    service.sync_sent(limit: 50)

    mail_account.custom_folders.each do |folder|
      service.sync_folder(folder, limit: 50)
    end
  # Every failure is shown on the account, or the mail page says "Syncing..." forever.
  # A rejected login waits for new settings or a sync by hand, a server that can't be reached
  # is tried again on the next scheduled sync. Unexpected failures still fail the job, so they can be looked into.
  rescue ::ImapSyncService::ConnectionError, ::ImapSyncService::AuthenticationError => e
    Rails.logger.error("Mail sync failed for account #{mail_account_id}: #{e.message}")
    mail_account.mark_sync_error!(e.message)
  rescue StandardError => e
    mail_account&.mark_sync_error!(e.message)
    raise
  end
end

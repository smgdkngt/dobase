# frozen_string_literal: true

class SyncEmailsJob < ApplicationJob
  queue_as :default

  # The mail page asks for a sync every minute in every open tab. One sync per account at a time is enough.
  limits_concurrency key: ->(mail_account_id) { mail_account_id }, duration: 15.minutes, on_conflict: :discard

  def perform(mail_account_id)
    mail_account = Mails::Account.find_by(id: mail_account_id)
    return unless mail_account

    service = ::ImapSyncService.new(mail_account)
    service.sync_folders
    service.sync_inbox(limit: 50)
    service.sync_sent(limit: 50)

    mail_account.custom_folders.each do |folder|
      service.sync_folder(folder, limit: 50)
    end
  rescue ::ImapSyncService::ConnectionError, ::ImapSyncService::AuthenticationError => e
    Rails.logger.error("Mail sync failed for account #{mail_account_id}: #{e.message}")
  end
end

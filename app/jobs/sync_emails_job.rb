# frozen_string_literal: true

class SyncEmailsJob < ApplicationJob
  queue_as :default

  def perform(mail_account_id)
    mail_account = Mails::Account.find_by(id: mail_account_id)
    return unless mail_account

    service = ::ImapSyncService.new(mail_account)
    service.sync_folders
    service.sync_inbox(limit: 50)
    service.sync_sent(limit: 20)

    mail_account.custom_folders.each do |folder|
      service.sync_folder(folder, limit: 20)
    end
  rescue ::ImapSyncService::ConnectionError, ::ImapSyncService::AuthenticationError => e
    Rails.logger.error("Mail sync failed for account #{mail_account_id}: #{e.message}")
  end
end

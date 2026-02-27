# frozen_string_literal: true

class SyncCalendarsJob < ApplicationJob
  queue_as :default

  def perform(calendar_account_id)
    account = Calendars::Account.find_by(id: calendar_account_id)
    return unless account

    account.mark_syncing!

    service = CaldavSyncService.new(account)

    # Always rediscover calendars to pick up new/deleted calendars
    service.discover_calendars

    # Sync all enabled calendars
    service.sync_all_calendars

    account.mark_synced!
  rescue CaldavSyncService::AuthenticationError => e
    Rails.logger.error("Calendar sync authentication failed for account #{calendar_account_id}: #{e.message}")
    account.mark_sync_error!("Authentication failed: #{e.message}")
  rescue CaldavSyncService::ConnectionError => e
    Rails.logger.error("Calendar sync connection failed for account #{calendar_account_id}: #{e.message}")
    account.mark_sync_error!("Connection failed: #{e.message}")
  rescue CaldavSyncService::SyncError => e
    Rails.logger.error("Calendar sync failed for account #{calendar_account_id}: #{e.message}")
    account.mark_sync_error!(e.message)
  rescue StandardError => e
    Rails.logger.error("Calendar sync unexpected error for account #{calendar_account_id}: #{e.message}")
    account.mark_sync_error!("Unexpected error: #{e.message}")
  end
end

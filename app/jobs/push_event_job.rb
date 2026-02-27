# frozen_string_literal: true

class PushEventJob < ApplicationJob
  queue_as :default

  def perform(event_id, action)
    event = Calendars::Event.find_by(id: event_id)

    # For delete, we need the event data even if soft-deleted
    event ||= Calendars::Event.unscoped.find_by(id: event_id) if action.to_sym == :delete

    return unless event

    account = event.calendar.account
    service = CaldavSyncService.new(account)

    case action.to_sym
    when :create
      service.create_event(event)
    when :update
      service.update_event(event)
    when :delete
      service.delete_event(event)
    else
      Rails.logger.warn("PushEventJob: Unknown action #{action} for event #{event_id}")
    end
  rescue CaldavSyncService::SyncError => e
    Rails.logger.error("Failed to push event #{event_id} (#{action}): #{e.message}")
    # Could implement retry logic or mark event as needing sync
  rescue CaldavSyncService::ConnectionError, CaldavSyncService::AuthenticationError => e
    Rails.logger.error("Connection error pushing event #{event_id}: #{e.message}")
    # Re-raise to trigger job retry
    raise
  end
end

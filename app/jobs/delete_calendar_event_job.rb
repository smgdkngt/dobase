# frozen_string_literal: true

class DeleteCalendarEventJob < ApplicationJob
  queue_as :default
  skip_in_demo

  retry_on CaldavSyncService::ConnectionError, wait: :polynomially_longer, attempts: 5

  # The event is gone from Dobase already, so event_data holds what the server needs to find it
  def perform(event_data)
    event_data = event_data.with_indifferent_access
    calendar = Calendars::Calendar.find_by(id: event_data[:calendar_id])
    return unless calendar

    remote_href = event_data[:remote_href]
    # Construct remote_href from calendar URL + UID if not set
    if remote_href.blank? && event_data[:uid].present? && calendar.remote_url.present?
      remote_href = "#{calendar.remote_url}#{event_data[:uid]}.ics"
    end

    return unless remote_href.present?

    event = Calendars::Event.new(calendar: calendar, remote_href: remote_href, etag: event_data[:etag])
    CaldavSyncService.new(calendar.account).delete_event(event)
  rescue CaldavSyncService::SyncError => e
    Rails.logger.error("Failed to delete event from CalDAV: #{e.message}")
  rescue CaldavSyncService::ConnectionError, CaldavSyncService::AuthenticationError => e
    Rails.logger.error("Connection error deleting event: #{e.message}")
    raise # Retry
  end
end

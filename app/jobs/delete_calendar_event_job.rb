# frozen_string_literal: true

class DeleteCalendarEventJob < ApplicationJob
  queue_as :default

  def perform(event_data)
    remote_href = event_data[:remote_href] || event_data["remote_href"]
    etag = event_data[:etag] || event_data["etag"]
    calendar_id = event_data[:calendar_id] || event_data["calendar_id"]
    uid = event_data[:uid] || event_data["uid"]

    calendar = Calendars::Calendar.find_by(id: calendar_id)
    return unless calendar

    # Construct remote_href from calendar URL + UID if not set
    if remote_href.blank? && uid.present? && calendar.remote_url.present?
      remote_href = "#{calendar.remote_url}#{uid}.ics"
    end

    return unless remote_href.present?

    account = calendar.account
    service = CaldavSyncService.new(account)

    # Build a minimal event-like object for the delete method
    event_stub = OpenStruct.new(
      remote_href: remote_href,
      etag: etag
    )

    service.delete_event(event_stub)
  rescue CaldavSyncService::SyncError => e
    Rails.logger.error("Failed to delete event from CalDAV: #{e.message}")
  rescue CaldavSyncService::ConnectionError, CaldavSyncService::AuthenticationError => e
    Rails.logger.error("Connection error deleting event: #{e.message}")
    raise # Retry
  end
end

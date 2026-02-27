# frozen_string_literal: true

class SyncCalendarPropertiesJob < ApplicationJob
  queue_as :default

  def perform(calendar_id)
    calendar = Calendars::Calendar.find_by(id: calendar_id)
    return unless calendar
    return if calendar.local?

    service = CaldavSyncService.new(calendar.account)
    service.update_calendar(calendar)
  rescue CaldavSyncService::SyncError => e
    Rails.logger.error("Failed to sync calendar properties: #{e.message}")
  end
end

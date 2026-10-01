# frozen_string_literal: true

class PushEventJob < ApplicationJob
  queue_as :default
  skip_in_demo

  retry_on CaldavSyncService::ConnectionError, wait: :polynomially_longer, attempts: 5

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
    when :move
      service.move_event(event)
    when :delete
      service.delete_event(event)
    else
      Rails.logger.warn("PushEventJob: Unknown action #{action} for event #{event_id}")
    end
  rescue CaldavSyncService::SyncError => e
    Rails.logger.error("Failed to push event #{event_id} (#{action}): #{e.message}")
    note_refusal(service, event) if e.is_a?(CaldavSyncService::ForbiddenError)
  rescue CaldavSyncService::AuthenticationError => e
    # Trying again gets the same answer, so it shows on the account instead
    Rails.logger.error("Failed to push event #{event_id} (#{action}): #{e.message}")
    event.calendar.account.mark_sync_error!(e.message)
  rescue CaldavSyncService::ConnectionError => e
    Rails.logger.error("Connection error pushing event #{event_id}: #{e.message}")
    # Re-raise to trigger job retry
    raise
  end

  private

  # A refused event doesn't have to mean its calendar is read-only: servers also refuse changes to
  # an event someone else organizes. So the server is asked what the user may do with the calendar,
  # and only when it doesn't say is a refused event of the user's own taken as the sign.
  def note_refusal(service, event)
    calendar = event.calendar
    read_only = begin
      service.refresh_write_access(calendar)
    rescue CaldavSyncService::ConnectionError, CaldavSyncService::AuthenticationError, CaldavSyncService::SyncError
      nil
    end

    calendar.update!(read_only: true) if read_only.nil? && !organized_by_someone_else?(event)
    Rails.logger.warn("Marked calendar '#{calendar.name}' as read-only (403 from server)") if calendar.read_only?
  end

  def organized_by_someone_else?(event)
    event.organizer_email.present? && !event.organizer_email.casecmp?(event.calendar.account.username.to_s)
  end
end

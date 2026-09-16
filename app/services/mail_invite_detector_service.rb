# frozen_string_literal: true

class MailInviteDetectorService
  # calendar_data: an invitation that isn't an attachment, like the inline
  # text/calendar part Outlook sends, found while the message was parsed
  def initialize(message, calendar_data: nil)
    @message = message
    @calendar_data = calendar_data
  end

  def detect_and_create_invite
    ics_data = find_calendar_data
    return nil unless ics_data.present?

    parsed = IcsParserService.new(ics_data).parse
    return nil unless parsed[:uid].present?

    create_or_update_invite(parsed)
  end

  private

  def find_calendar_data
    # First, check for text/calendar attachments
    calendar_attachment = @message.attachments.find do |att|
      att.content_type&.start_with?("text/calendar") ||
        att.filename&.end_with?(".ics")
    end

    if calendar_attachment&.file&.attached?
      # Active Storage hands back binary; iCalendar data is UTF-8 (RFC 5545)
      return calendar_attachment.file.download.force_encoding(Encoding::UTF_8).scrub
    end

    @calendar_data.presence
  end

  def create_or_update_invite(parsed)
    invite = @message.calendar_invites.find_or_initialize_by(uid: parsed[:uid])

    # Determine status based on method
    status = case parsed[:method]
    when "CANCEL"
      "cancelled"
    when "REPLY"
      # Keep existing status or set to pending
      invite.status || "pending"
    else
      invite.new_record? ? "pending" : invite.status
    end

    invite.assign_attributes(
      method: parsed[:method],
      summary: parsed[:summary],
      description: parsed[:description],
      location: parsed[:location],
      starts_at: parsed[:starts_at],
      ends_at: parsed[:ends_at],
      all_day: parsed[:all_day],
      organizer_email: parsed[:organizer_email],
      organizer_name: parsed[:organizer_name],
      attendees_json: parsed[:attendees].to_json,
      raw_icalendar: parsed[:raw_icalendar],
      status: status
    )

    invite.save!
    # A cancelled event can't be accepted from its earlier invitations anymore
    invite.same_event_invitations.where(status: %w[pending tentative]).update_all(status: "cancelled") if invite.cancelled?
    invite
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to create calendar invite: #{e.message}")
    nil
  end
end

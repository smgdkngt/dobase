# frozen_string_literal: true

class MailInviteDetectorService
  def initialize(message)
    @message = message
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
      return calendar_attachment.file.download
    end

    # If no attachment, try to parse from raw message body
    # Some email clients embed calendar data directly in the message
    if @message.respond_to?(:raw_message) && @message.raw_message.present?
      mail = Mail.read_from_string(@message.raw_message)

      # Look for text/calendar parts
      mail.parts.each do |part|
        if part.content_type&.include?("text/calendar")
          return part.decoded
        end

        # Check nested parts (multipart/alternative, etc.)
        if part.multipart?
          part.parts.each do |nested|
            if nested.content_type&.include?("text/calendar")
              return nested.decoded
            end
          end
        end
      end
    end

    nil
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
    invite
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to create calendar invite: #{e.message}")
    nil
  end
end

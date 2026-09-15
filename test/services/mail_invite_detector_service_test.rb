# frozen_string_literal: true

require "test_helper"

class MailInviteDetectorServiceTest < ActiveSupport::TestCase
  setup do
    @message = mails_messages(:inbox_unread)
  end

  test "creates an invite from an .ics attachment" do
    attach_ics <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      METHOD:REQUEST
      BEGIN:VEVENT
      UID:planning-123@example.com
      DTSTART:20261001T090000Z
      DTEND:20261001T100000Z
      SUMMARY:Quarterly planning
      LOCATION:Room 4
      ORGANIZER;CN=Olivia Organizer:mailto:olivia@example.com
      ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED;ROLE=REQ-PARTICIPANT:mailto:alice@example.com
      ATTENDEE;CN=Test User;PARTSTAT=NEEDS-ACTION;ROLE=REQ-PARTICIPANT;RSVP=TRUE:mailto:testuser@example.com
      END:VEVENT
      END:VCALENDAR
    ICS

    assert_difference -> { @message.calendar_invites.count }, 1 do
      MailInviteDetectorService.new(@message).detect_and_create_invite
    end

    invite = @message.calendar_invites.find_by!(uid: "planning-123@example.com")
    assert_equal [ "REQUEST", "pending" ], [ invite.method, invite.status ]
    assert_equal [ "Quarterly planning", "Room 4" ], [ invite.summary, invite.location ]
    assert_equal [ Time.utc(2026, 10, 1, 9), Time.utc(2026, 10, 1, 10) ], [ invite.starts_at, invite.ends_at ]
    assert_equal [ "olivia@example.com", "Olivia Organizer" ], [ invite.organizer_email, invite.organizer_name ]
    assert_equal [
      { "email" => "alice@example.com", "name" => "Alice", "status" => "accepted", "role" => "req-participant", "rsvp" => false },
      { "email" => "testuser@example.com", "name" => "Test User", "status" => "needs-action", "role" => "req-participant", "rsvp" => true }
    ], invite.attendees
  end

  private
    def attach_ics(ics)
      attachment = @message.attachments.create!(filename: "invite.ics", content_type: "text/calendar", file_size: ics.bytesize)
      attachment.file.attach(io: StringIO.new(ics), filename: "invite.ics", content_type: "text/calendar")
    end
end

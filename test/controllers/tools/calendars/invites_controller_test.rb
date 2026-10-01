# frozen_string_literal: true

require "test_helper"

module Tools
  module Calendars
    class InvitesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @calendar_tool = tools(:my_calendar)
        @own_invite = invite_for(mails_messages(:inbox_unread), summary: "Planning session")
        @foreign_invite = invite_for(mails_messages(:other_inbox), summary: "Board meeting")
      end

      test "accepting an invite from your own mail adds it to the calendar with its attendees" do
        attendees = [
          { "email" => "alice@example.com", "name" => "Alice", "status" => "accepted", "role" => "req-participant", "rsvp" => false },
          { "email" => "one@example.com", "name" => "User One", "status" => "needs-action", "role" => "req-participant", "rsvp" => true }
        ]
        @own_invite.update!(attendees_json: attendees.to_json)
        calendar = calendars_calendars(:personal)

        email_url = tool_mail_url(tools(:my_mail), mails_messages(:inbox_unread))

        assert_difference -> { calendar.events.count }, 1 do
          post tool_calendar_invites_path(@calendar_tool), params: { invite_id: @own_invite.id, calendar_id: calendar.id },
                                                           headers: { "HTTP_REFERER" => email_url }
        end

        assert_redirected_to email_url
        event = calendar.events.find_by!(uid: @own_invite.uid)
        assert_equal [ "Planning session", attendees ], [ event.summary, event.attendees ]
        @own_invite.reload
        assert_equal [ "accepted", calendar, event ], [ @own_invite.status, @own_invite.added_to_calendar, @own_invite.created_event ]
        assert_enqueued_with job: PushEventJob, args: [ event.id, :create ]
      end

      test "accepting an all-day invite west of UTC adds an all-day event on the same dates" do
        users(:one).update!(timezone: "Pacific Time (US & Canada)")
        @own_invite.update!(all_day: true, starts_at: Time.utc(2030, 1, 10), ends_at: Time.utc(2030, 1, 12))
        calendar = calendars_calendars(:personal)

        post tool_calendar_invites_path(@calendar_tool), params: { invite_id: @own_invite.id, calendar_id: calendar.id }

        event = calendar.events.find_by!(uid: @own_invite.uid)
        assert event.all_day?
        assert_equal [ Time.utc(2030, 1, 10), Time.utc(2030, 1, 12) ], [ event.starts_at, event.ends_at ]
        Time.use_zone("America/Los_Angeles") do
          assert_equal [ Date.new(2030, 1, 10), Date.new(2030, 1, 11) ], [ event.first_day, event.last_day ]
        end
      end

      test "accepting an invitation to a series adds the whole series, with its skipped and moved occurrences" do
        ics = <<~ICS
          BEGIN:VCALENDAR
          METHOD:REQUEST
          PRODID:Microsoft Exchange Server 2010
          VERSION:2.0
          BEGIN:VTIMEZONE
          TZID:W. Europe Standard Time
          BEGIN:STANDARD
          DTSTART:16010101T030000
          TZOFFSETFROM:+0200
          TZOFFSETTO:+0100
          RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
          END:STANDARD
          BEGIN:DAYLIGHT
          DTSTART:16010101T020000
          TZOFFSETFROM:+0100
          TZOFFSETTO:+0200
          RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
          END:DAYLIGHT
          END:VTIMEZONE
          BEGIN:VEVENT
          UID:weekly-sync@example.com
          DTSTART;TZID=W. Europe Standard Time:20301007T100000
          DTEND;TZID=W. Europe Standard Time:20301007T103000
          RRULE:FREQ=WEEKLY;COUNT=5
          EXDATE;TZID=W. Europe Standard Time:20301014T100000
          SUMMARY:Weekly sync
          END:VEVENT
          BEGIN:VEVENT
          UID:weekly-sync@example.com
          RECURRENCE-ID;TZID=W. Europe Standard Time:20301021T100000
          DTSTART;TZID=W. Europe Standard Time:20301021T140000
          DTEND;TZID=W. Europe Standard Time:20301021T143000
          SUMMARY:Weekly sync (afternoon)
          END:VEVENT
          END:VCALENDAR
        ICS
        users(:one).update!(timezone: "Eastern Time (US & Canada)")
        invite = mails_messages(:inbox_unread).calendar_invites.create!(uid: "weekly-sync@example.com", summary: "Weekly sync", status: "pending",
          starts_at: Time.utc(2030, 10, 7, 8), ends_at: Time.utc(2030, 10, 7, 8, 30), raw_icalendar: ics)
        calendar = calendars_calendars(:personal)

        post tool_calendar_invites_path(@calendar_tool), params: { invite_id: invite.id, calendar_id: calendar.id }

        event = calendar.events.find_by!(uid: "weekly-sync@example.com")
        assert event.is_recurring?
        assert_equal "FREQ=WEEKLY;COUNT=5", event.rrule
        # 10:00 in Amsterdam, before and after the clocks go back on October 27th; the 14th is skipped, the 21st moved
        assert_equal [ Time.utc(2030, 10, 7, 8), Time.utc(2030, 10, 28, 9), Time.utc(2030, 11, 4, 9) ],
          IceCube::Schedule.from_yaml(event.recurrence_schedule).all_occurrences.map(&:utc)
        assert_equal [ [ Time.utc(2030, 10, 21, 12), "Weekly sync (afternoon)" ] ],
          event.recurrence_overrides.map { |override| [ Time.iso8601(override["starts_at"]).utc, override["summary"] ] }

        get tool_calendar_path(@calendar_tool, format: :json), params: { start_date: "2030-10-01", end_date: "2030-11-10" }
        starts = response.parsed_body["events"].select { |listed| listed["uid"] == "weekly-sync@example.com" }.map { |listed| Time.iso8601(listed["starts_at"]).utc }
        assert_equal [ Time.utc(2030, 10, 7, 8), Time.utc(2030, 10, 21, 12), Time.utc(2030, 10, 28, 9), Time.utc(2030, 11, 4, 9) ], starts
      end

      test "accepting an invite without a title adds an untitled event" do
        @own_invite.update!(summary: nil)
        calendar = calendars_calendars(:personal)

        post tool_calendar_invites_path(@calendar_tool), params: { invite_id: @own_invite.id, calendar_id: calendar.id }

        assert_equal "(No title)", calendar.events.find_by!(uid: @own_invite.uid).summary
        assert_equal "accepted", @own_invite.reload.status
      end

      test "cannot accept an invite from mail the user has no access to" do
        assert_no_difference -> { ::Calendars::Event.count } do
          post tool_calendar_invites_path(@calendar_tool),
               params: { invite_id: @foreign_invite.id, calendar_id: calendars_calendars(:personal).id }
        end

        assert_redirected_to root_path
        assert_equal "pending", @foreign_invite.reload.status
        assert_not ::Calendars::Event.exists?(summary: "Board meeting")
      end

      test "declining an invite from your own mail" do
        delete tool_calendar_invite_path(@calendar_tool, @own_invite)

        assert_equal "declined", @own_invite.reload.status
      end

      test "cannot decline an invite from mail the user has no access to" do
        delete tool_calendar_invite_path(@calendar_tool, @foreign_invite)

        assert_redirected_to root_path
        assert_equal "pending", @foreign_invite.reload.status
      end

      private

      def invite_for(message, summary:)
        message.calendar_invites.create!(
          uid: "#{SecureRandom.uuid}@example.com",
          summary: summary,
          starts_at: 2.days.from_now,
          ends_at: 2.days.from_now + 1.hour,
          status: "pending"
        )
      end
    end
  end
end

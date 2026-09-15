# frozen_string_literal: true

require "test_helper"

module Calendars
  class InviteTest < ActiveSupport::TestCase
    test "deleting the event an accepted invite created keeps the invite" do
      invite = accepted_invite
      invite.created_event.destroy

      assert_nil invite.reload.created_event_id
    end

    test "deleting the calendar an invite was added to keeps the invite" do
      invite = accepted_invite
      invite.added_to_calendar.destroy

      invite.reload
      assert_equal [ nil, nil ], [ invite.added_to_calendar_id, invite.created_event_id ]
    end

    test "duration_display pluralizes minutes, hours and days" do
      starts_at = Time.utc(2026, 10, 1, 9)
      durations = [ 1.minute, 45.minutes, 1.hour, 90.minutes, 3.hours, 1.day, 36.hours ].map do |length|
        Invite.new(starts_at: starts_at, ends_at: starts_at + length).duration_display
      end

      assert_equal [ "1 minute", "45 minutes", "1 hour", "1.5 hours", "3 hours", "1 day", "1.5 days" ], durations
    end

    test "last_day of an all-day invite is the day before its exclusive end" do
      one_day = Invite.new(all_day: true, starts_at: Time.utc(2026, 10, 1), ends_at: Time.utc(2026, 10, 2))
      three_days = Invite.new(all_day: true, starts_at: Time.utc(2026, 10, 1), ends_at: Time.utc(2026, 10, 4))

      assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 10, 3) ], [ one_day.last_day, three_days.last_day ]
    end

    private
      def accepted_invite
        event = calendars_events(:meeting)
        mails_messages(:inbox_unread).calendar_invites.create!(
          uid: event.uid, summary: event.summary, starts_at: event.starts_at, ends_at: event.ends_at,
          status: "accepted", added_to_calendar: event.calendar, created_event: event
        )
      end
  end
end

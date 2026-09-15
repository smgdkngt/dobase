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

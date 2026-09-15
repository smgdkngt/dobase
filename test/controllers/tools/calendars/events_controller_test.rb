# frozen_string_literal: true

require "test_helper"

module Tools
  module Calendars
    class EventsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_calendar)
        @meeting = calendars_events(:meeting)
      end

      test "update moves an event to another calendar of the same account" do
        patch tool_calendar_event_path(@tool, @meeting), params: {
          calendars_event: { calendar_id: calendars_calendars(:work).id, summary: "Renamed", recurrence_frequency: "none" }
        }

        assert_redirected_to tool_calendar_path(@tool)
        assert_equal [ "Renamed", calendars_calendars(:work) ], [ @meeting.reload.summary, @meeting.calendar ]
        assert_enqueued_with job: PushEventJob, args: [ @meeting.id, :update ]
      end

      test "update can't move an event to a calendar of another tool" do
        foreign_calendar = calendars_accounts(:pending_account).calendars.create!(name: "Theirs", remote_id: "/theirs/")

        patch tool_calendar_event_path(@tool, @meeting), params: { calendars_event: { calendar_id: foreign_calendar.id } }

        assert_redirected_to root_path
        assert_equal calendars_calendars(:personal), @meeting.reload.calendar
        assert_no_enqueued_jobs only: PushEventJob
      end
    end
  end
end

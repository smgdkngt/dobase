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

      test "the edit form shows the times of an event, and the days of an all-day event" do
        users(:one).update!(timezone: "Eastern Time (US & Canada)")
        holiday = calendars_calendars(:personal).events.create!(uid: "holiday@dobase", summary: "Holiday", all_day: true,
          starts_at: Time.utc(2030, 1, 8), ends_at: Time.utc(2030, 1, 10))

        get edit_tool_calendar_event_path(@tool, @meeting)
        meeting_start = @meeting.starts_at.in_time_zone("Eastern Time (US & Canada)")
        assert_select "input[name='calendars_event[start_time]'][value=?]", meeting_start.strftime("%Y-%m-%dT%H:%M:%S")

        get edit_tool_calendar_event_path(@tool, holiday)
        assert_select "input[name='calendars_event[start_time]'][value='2030-01-08T00:00:00']"
        assert_select "input[name='calendars_event[end_time]'][value='2030-01-09T23:59:00']"
      end
    end
  end
end

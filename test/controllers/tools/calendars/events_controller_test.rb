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

        assert_redirected_to calendar_path_showing(@meeting)
        assert_equal [ "Renamed", calendars_calendars(:work) ], [ @meeting.reload.summary, @meeting.calendar ]
        assert_enqueued_with job: PushEventJob, args: [ @meeting.id, :move ]
      end

      test "an update in the same calendar pushes the change" do
        patch tool_calendar_event_path(@tool, @meeting), params: {
          calendars_event: { calendar_id: @meeting.calendar_id, summary: "Renamed" }
        }

        assert_redirected_to calendar_path_showing(@meeting)
        assert_enqueued_with job: PushEventJob, args: [ @meeting.id, :update ]
      end

      test "a failed update offers only calendars that take events" do
        calendars_calendars(:work).update!(read_only: true)

        patch tool_calendar_event_path(@tool, @meeting), params: {
          calendars_event: { summary: "Backwards", start_time: "2030-01-08T15:00", end_time: "2030-01-08T14:00" }
        }

        assert_response :unprocessable_entity
        assert_select "select[name='calendars_event[calendar_id]'] option" do |options|
          assert_equal [ "", "Personal" ], options.map(&:text)
        end
      end

      test "the edit form cancels by closing the event dialog, or on its own page by going back to the calendar" do
        get edit_tool_calendar_event_path(@tool, @meeting), headers: { "Turbo-Frame" => "event_modal_content" }
        assert_select "form:not([data-turbo-frame]) button[type=button][data-action='click->modal#close']", text: "Cancel"

        get edit_tool_calendar_event_path(@tool, @meeting)
        assert_select "a[href='#{tool_calendar_path(@tool)}'][data-turbo-frame='_top']", text: "Cancel"
      end

      test "an event shows in a card with a way back on a page of its own, and bare in the event dialog" do
        get tool_calendar_event_path(@tool, @meeting)
        assert_select ".card .event-details"
        assert_select "a[href=?]", tool_calendar_path(@tool, week_start: @meeting.first_day), text: "Back to calendar"
        assert_select "a[data-turbo-frame='_top']", text: "Edit"

        get tool_calendar_event_path(@tool, @meeting), headers: { "X-Requested-With" => "XMLHttpRequest" }
        assert_select ".card", count: 0
        assert_select "button[data-action='click->modal#close']", text: "Close"
        assert_select "a[data-turbo-frame='event_modal_content']", text: "Edit"

        get edit_tool_calendar_event_path(@tool, @meeting)
        assert_select ".card .event-edit-form"
      end

      test "update can't move an event to a calendar of another tool" do
        foreign_calendar = calendars_accounts(:pending_account).calendars.create!(name: "Theirs", remote_id: "/theirs/")

        patch tool_calendar_event_path(@tool, @meeting), params: { calendars_event: { calendar_id: foreign_calendar.id } }

        assert_redirected_to root_path
        assert_equal calendars_calendars(:personal), @meeting.reload.calendar
        assert_no_enqueued_jobs only: PushEventJob
      end

      test "the calendar page answers a form's redirect with a refresh, or with the week the redirect names" do
        stream = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

        get tool_calendar_path(@tool), headers: stream
        assert_equal "text/vnd.turbo-stream.html", response.media_type
        assert_select "turbo-stream[action=refresh]"

        get tool_calendar_path(@tool, week_start: "2030-01-28"), headers: stream
        assert_equal "text/html", response.media_type
        assert_select "h1", text: /Jan.*Feb 2030/
      end

      test "a change goes back to the week it was made from while the event shows there" do
        viewed = { "Referer" => tool_calendar_url(@tool, week_start: "2030-01-07") }
        trip = calendars_calendars(:personal).events.create!(uid: "trip@dobase", summary: "Trip",
          starts_at: Time.utc(2030, 1, 4, 9), ends_at: Time.utc(2030, 1, 9, 17))
        standup = calendars_calendars(:personal).events.create!(uid: "standup@dobase", summary: "Standup",
          starts_at: Time.utc(2029, 6, 4, 9), ends_at: Time.utc(2029, 6, 4, 10), recurrence_frequency: "weekly")

        # Began the week before, still going in the one being looked at
        patch tool_calendar_event_path(@tool, trip), params: { calendars_event: { summary: "Long trip" } }, headers: viewed
        assert_redirected_to tool_calendar_path(@tool, week_start: "2030-01-07")

        # A series started long ago: the week it was opened from, not the one it started in
        patch tool_calendar_event_path(@tool, standup), params: { calendars_event: { summary: "Daily" } }, headers: viewed
        assert_redirected_to tool_calendar_path(@tool, week_start: "2030-01-07")

        # Moved out of the week: follow it
        patch tool_calendar_event_path(@tool, trip), params: {
          calendars_event: { start_time: "2030-02-13T09:00", end_time: "2030-02-13T17:00" }
        }, headers: viewed
        assert_redirected_to tool_calendar_path(@tool, week_start: "2030-02-11")

        delete tool_calendar_event_path(@tool, trip), headers: viewed
        assert_redirected_to tool_calendar_path(@tool, week_start: "2030-01-07")
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

      private

      # The fixtures' meeting is tomorrow, which on a Sunday is next week
      def calendar_path_showing(event)
        monday = event.first_day.beginning_of_week(:monday)
        tool_calendar_path(@tool, week_start: (monday unless monday == Date.current.beginning_of_week(:monday)))
      end
    end
  end
end

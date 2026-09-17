# frozen_string_literal: true

require "test_helper"

module Tools
  class CalendarsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_calendar)
      @personal = calendars_calendars(:personal)
      @work = calendars_calendars(:work)
      @meeting = calendars_events(:meeting)
    end

    test "week view shows the events of the week" do
      get tool_calendar_path(@tool, week_start: @meeting.starts_at.to_date.iso8601)

      assert_response :success
      assert_includes response.body, "Team Meeting"
    end

    test "week view shows the days in the user's time zone" do
      users(:one).update!(timezone: "Eastern Time (US & Canada)")
      # Tuesday 22:00 in New York until 03:00 the next morning
      @personal.events.create!(uid: "night-shift@dobase", summary: "Night shift", starts_at: Time.utc(2030, 1, 9, 3), ends_at: Time.utc(2030, 1, 9, 8))

      # Still Tuesday in New York, Wednesday in UTC
      travel_to Time.utc(2030, 1, 9, 2) do
        get tool_calendar_path(@tool, week_start: "2030-01-07")
      end

      assert_select ".week-header-cell.today", text: /Tue\s+8/
      assert_match "top: 91.66", css_select(".week-column[data-date='2030-01-08'] [data-event-id]").sole["style"]
      assert_match "top: 0.0%", css_select(".week-column[data-date='2030-01-09'] [data-event-id]").sole["style"]
    end

    test "week view shows all-day events on their dates west of UTC" do
      users(:one).update!(timezone: "Eastern Time (US & Canada)")
      # As synced: DTSTART;VALUE=DATE:20300108 and DTEND;VALUE=DATE:20300109
      @personal.events.create!(uid: "holiday@dobase", summary: "Holiday", all_day: true, starts_at: Time.utc(2030, 1, 8), ends_at: Time.utc(2030, 1, 9))
      @personal.events.create!(uid: "trip@dobase", summary: "Trip", all_day: true, starts_at: Time.utc(2030, 1, 10), ends_at: Time.utc(2030, 1, 14))
      @personal.events.create!(uid: "next-monday@dobase", summary: "Next Monday", all_day: true, starts_at: Time.utc(2030, 1, 14), ends_at: Time.utc(2030, 1, 15))

      get tool_calendar_path(@tool, week_start: "2030-01-07")

      spans = css_select(".all-day-event-span").to_h { |span| [ span.text.strip, span["style"][/grid-column: [^;]+/] ] }
      assert_equal({ "Holiday" => "grid-column: 2 / span 1", "Trip" => "grid-column: 4 / span 4" }, spans)
    end

    test "week view lays out overlapping, short and long events" do
      create = ->(summary, starts, ends) { @personal.events.create!(uid: "#{summary}@dobase", summary: summary, starts_at: starts, ends_at: ends) }
      create.("Design review", Time.utc(2030, 1, 9, 12), Time.utc(2030, 1, 9, 13, 30))
      create.("Call", Time.utc(2030, 1, 9, 12, 30), Time.utc(2030, 1, 9, 13))
      create.("Conference", Time.utc(2030, 1, 9, 9), Time.utc(2030, 1, 11, 17))
      create.("Late", Time.utc(2030, 1, 10, 22), Time.utc(2030, 1, 11))

      get tool_calendar_path(@tool, week_start: "2030-01-07")

      blocks = css_select(".week-column [data-event-id]").to_h { |block| [ block.text.squish, block["style"] ] }
      assert_match "left: calc(0.0% + 2px); width: calc(50.0% - 4px)", blocks["12:00 Design review"]
      assert_match "left: calc(50.0% + 2px); width: calc(50.0% - 4px)", blocks["12:30 Call"]
      assert_match "height: 2.08", blocks["12:30 Call"]
      assert_equal [ "12:00 Design review", "12:30 Call", "22:00 Late" ], blocks.keys
      assert_select ".all-day-event-span", text: "09:00 Conference" do |spans|
        assert_match "grid-column: 3 / span 3", spans.sole["style"]
      end
    end

    test "the new event form repeats on the start's weekday and never ends, until told otherwise" do
      travel_to Time.utc(2030, 1, 9, 10, 30) do
        get tool_calendar_path(@tool)
      end

      assert_select "#new-event-modal" do
        assert_select "input[name='calendars_event[recurrence_end_type]'][checked]" do |radios|
          assert_equal [ "never" ], radios.map { |radio| radio["value"] }
        end
        assert_select "input[name='calendars_event[recurrence_days_of_week][]'][checked]" do |days|
          assert_equal [ "WE" ], days.map { |day| day["value"] }
        end
        assert_select "[data-recurrence-form-target=weekdayLabel]", text: "The 2nd Wednesday"
      end
    end

    test "the new event form offers only calendars that take new events" do
      @personal.update!(read_only: true)

      get tool_calendar_path(@tool)

      assert_select "#new-event-modal select[name='calendars_event[calendar_id]'] option" do |options|
        assert_equal [ [ "", nil ], [ "Work", "selected" ] ], options.map { |option| [ option.text, option["selected"] ] }
      end
    end

    test "week view sends owners without an account to the account setup" do
      tool = Tool.create!(name: "Unconnected", tool_type: tool_types(:calendar), owner: users(:one))

      get tool_calendar_path(tool)

      assert_redirected_to new_tool_calendar_account_path(tool)
    end

    test "week view tells collaborators the owner hasn't connected a calendar account yet" do
      tool = Tool.create!(name: "Team Calendar", tool_type: tool_types(:calendar), owner: users(:one))
      tool.collaborators.create!(user: users(:two), role: "collaborator")
      sign_in_as users(:two)

      get tool_path(tool)
      assert_redirected_to tool_calendar_path(tool)
      follow_redirect!

      assert_response :success
      assert_select "h1", "Team Calendar"
      assert_select "div", text: "The owner of Team Calendar hasn't connected a calendar account yet. Once they have, the calendar shows up here."
    end

    test "creating an event redirects to the calendar" do
      post tool_calendar_events_path(@tool), params: {
        calendars_event: { calendar_id: @work.id, summary: "Dentist", start_time: "2030-01-08T14:00", end_time: "2030-01-08T15:00", recurrence_frequency: "none" }
      }

      assert_redirected_to tool_calendar_path(@tool)
      assert_equal "Event created successfully.", flash[:notice]
      assert_enqueued_with job: PushEventJob, args: [ @work.events.find_by!(summary: "Dentist").id, :create ]
    end

    test "creating an event on a read-only calendar shows the form again" do
      @work.update!(read_only: true)

      assert_no_difference -> { ::Calendars::Event.count } do
        post tool_calendar_events_path(@tool), params: {
          calendars_event: { calendar_id: @work.id, summary: "Dentist", start_time: "2030-01-08T14:00", end_time: "2030-01-08T15:00" }
        }
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "Calendar is read-only"
    end

    test "the event form names fields in its errors as its labels do" do
      post tool_calendar_events_path(@tool), params: {
        calendars_event: { calendar_id: @work.id, summary: "", start_time: "2030-01-08T15:00", end_time: "2030-01-08T14:00" }
      }

      assert_response :unprocessable_entity
      assert_select ".flash-error", text: "Title can't be blank"
      assert_select "label[for='calendars_event_summary']", text: "Title"
      assert_select "label[for='calendars_event_end_time']", text: "End"
    end

    test "deleting an event redirects to the calendar" do
      delete tool_calendar_event_path(@tool, @meeting)

      assert_redirected_to tool_calendar_path(@tool)
      assert_not ::Calendars::Event.exists?(@meeting.id)
      assert_enqueued_jobs 1, only: DeleteCalendarEventJob
    end

    test "syncing redirects to the calendar, or answers turbo streams with ok" do
      post tool_calendar_sync_path(@tool)
      assert_redirected_to tool_calendar_path(@tool)

      post tool_calendar_sync_path(@tool), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      assert_response :ok

      assert_enqueued_jobs 2, only: SyncCalendarsJob
    end
  end
end

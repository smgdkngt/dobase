# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

module Tools
  class CalendarApiTest < ActionDispatch::IntegrationTest
    setup do
      # Pushes to the CalDAV server happen in jobs, which these tests only enqueue.
      WebMock.disable_net_connect!

      @user = users(:one)
      @user.update!(timezone: "Amsterdam")
      @headers = api_headers(@user)
      @tool = tools(:my_calendar)
      @personal = calendars_calendars(:personal)
      @work = calendars_calendars(:work)
    end

    teardown do
      WebMock.allow_net_connect!
    end

    test "calendar lists the calendars and the events in a date range in start order" do
      create_event(@work, "Late review", "2030-01-13 23:00", "2030-01-13 23:30")
      create_event(@personal, "Dentist", "2030-01-08 14:00", "2030-01-08 15:00", location: "Main Street 1")
      create_event(@personal, "Next week", "2030-01-14 09:00", "2030-01-14 10:00")
      create_event(calendars_calendars(:disabled_calendar), "Hidden", "2030-01-09 09:00", "2030-01-09 10:00")

      get tool_calendar_path(@tool, start_date: "2030-01-07", end_date: "2030-01-13"), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal "2030-01-07", body["start_date"]
      assert_equal "2030-01-13", body["end_date"]
      assert_equal tool_calendar_url(@tool, week_start: "2030-01-07"), body["url"]
      assert_equal false, body["local"]
      assert_equal "synced", body.dig("sync", "status")

      assert_equal [ "Personal", "Work", "Disabled" ], body["calendars"].map { |calendar| calendar["name"] }
      personal = body["calendars"].first
      assert_equal [ true, true, false, true ], personal.values_at("is_default", "enabled", "read_only", "writable")
      assert_equal false, body["calendars"].last["writable"]

      assert_equal [ "Dentist", "Late review" ], body["events"].map { |event| event["summary"] }
      dentist = body["events"].first
      assert_equal "2030-01-08T14:00:00.000+01:00", dentist["starts_at"]
      assert_equal "2030-01-08T15:00:00.000+01:00", dentist["ends_at"]
      assert_equal "Main Street 1", dentist["location"]
      assert_equal({ "id" => @personal.id, "name" => "Personal", "color" => "#3b82f6" }, dentist["calendar"])
      assert_equal [ false, false ], dentist.values_at("recurring", "occurrence")
      assert_equal @user.email_address, dentist.dig("creator", "email_address")
      assert_equal tool_calendar_url(@tool, week_start: "2030-01-07"), dentist["url"]
    end

    test "calendar defaults to today and the six days after" do
      travel_to Time.find_zone("Amsterdam").local(2030, 1, 9, 12) do
        create_event(@personal, "Sixth day", "2030-01-15 09:00", "2030-01-15 10:00")
        create_event(@personal, "Seventh day", "2030-01-16 09:00", "2030-01-16 10:00")

        get tool_calendar_path(@tool), headers: @headers

        assert_response :success
        assert_equal [ "2030-01-09", "2030-01-15" ], response.parsed_body.values_at("start_date", "end_date")
        assert_equal [ "Sixth day" ], response.parsed_body["events"].map { |event| event["summary"] }
      end
    end

    test "calendar refuses invalid and overlong date ranges" do
      get tool_calendar_path(@tool, start_date: "2030-01-01", end_date: "2030-04-02"), headers: @headers
      assert_response :success

      get tool_calendar_path(@tool, start_date: "2030-01-01", end_date: "2030-04-03"), headers: @headers
      assert_response :unprocessable_entity
      assert_equal "The date range can't be longer than 92 days", response.parsed_body["error"]

      get tool_calendar_path(@tool, start_date: "2030-01-08", end_date: "2030-01-07"), headers: @headers
      assert_response :unprocessable_entity
      assert_equal "end_date can't be before start_date", response.parsed_body["error"]

      get tool_calendar_path(@tool, start_date: "next week"), headers: @headers
      assert_response :unprocessable_entity
      assert_match(/start_date must be a date/, response.parsed_body["error"])
    end

    test "recurring events are expanded into occurrences that carry the series id" do
      standup = create_event(@personal, "Standup", "2030-01-07 09:30", "2030-01-07 09:45",
        recurrence_frequency: "weekly", recurrence_days_of_week: %w[MO WE FR], recurrence_end_type: "never")

      get tool_calendar_path(@tool, start_date: "2030-01-07", end_date: "2030-01-13"), headers: @headers

      occurrences = response.parsed_body["events"]
      assert_equal [ standup.id ] * 3, occurrences.map { |event| event["id"] }
      assert_equal %w[2030-01-07T09:30:00.000+01:00 2030-01-09T09:30:00.000+01:00 2030-01-11T09:30:00.000+01:00],
        occurrences.map { |event| event["starts_at"] }
      assert_equal "2030-01-09T09:45:00.000+01:00", occurrences.second["ends_at"]
      assert_equal [ true, true ], occurrences.first.values_at("recurring", "occurrence")
      assert_equal "Weekly on Monday, Wednesday, Friday", occurrences.first["recurrence"]
      assert_equal "FREQ=WEEKLY;BYDAY=MO,WE,FR", occurrences.first["rrule"]
      assert_equal @user.email_address, occurrences.first.dig("creator", "email_address")

      # Occurrences keep their local time after the switch to summer time.
      get tool_calendar_path(@tool, start_date: "2030-04-01", end_date: "2030-04-01"), headers: @headers

      assert_equal [ "2030-04-01T09:30:00.000+02:00" ], response.parsed_body["events"].map { |event| event["starts_at"] }
    end

    test "all-day events keep their dates in every time zone" do
      @user.update!(timezone: "Eastern Time (US & Canada)")
      post tool_calendar_events_path(@tool), headers: @headers, as: :json, params: {
        calendars_event: { summary: "Offsite", all_day: true, start_time: "2030-01-10 00:00", end_time: "2030-01-11 23:59:59" }
      }
      assert_response :created
      assert_equal [ "2030-01-10T00:00:00.000-05:00", "2030-01-11T23:59:59.999-05:00" ], response.parsed_body.values_at("starts_at", "ends_at")
      # As synced: DTSTART;VALUE=DATE:20300109 and DTEND;VALUE=DATE:20300110
      @work.events.create!(uid: "holiday@test", summary: "Holiday", all_day: true, starts_at: Time.utc(2030, 1, 9), ends_at: Time.utc(2030, 1, 10))

      get tool_calendar_path(@tool, start_date: "2030-01-09", end_date: "2030-01-10"), headers: @headers

      assert_equal [
        [ "Holiday", "2030-01-09T00:00:00.000-05:00", "2030-01-09T23:59:59.999-05:00" ],
        [ "Offsite", "2030-01-10T00:00:00.000-05:00", "2030-01-11T23:59:59.999-05:00" ]
      ], response.parsed_body["events"].map { |event| event.values_at("summary", "starts_at", "ends_at") }

      @user.update!(timezone: "Amsterdam")
      get tool_calendar_path(@tool, start_date: "2030-01-10", end_date: "2030-01-10"), headers: @headers

      assert_equal [ [ "Offsite", "2030-01-10T00:00:00.000+01:00" ] ], response.parsed_body["events"].map { |event| event.values_at("summary", "starts_at") }
    end

    test "a repeating all-day event is listed on its dates after a change to summer time" do
      create_event(@personal, "Rent", "2030-01-10 00:00", "2030-01-10 23:59:59", all_day: true,
        recurrence_frequency: "monthly", recurrence_end_type: "never")

      get tool_calendar_path(@tool, start_date: "2030-07-09", end_date: "2030-07-11"), headers: @headers

      assert_equal [ [ "2030-07-10T00:00:00.000+02:00", "2030-07-10T23:59:59.999+02:00" ] ],
        response.parsed_body["events"].map { |event| event.values_at("starts_at", "ends_at") }
    end

    test "event shows a recurring event as the series" do
      standup = create_event(@personal, "Standup", "2030-01-07 09:30", "2030-01-07 09:45",
        recurrence_frequency: "daily", recurrence_end_type: "count", recurrence_count: 5, description: "Quick sync")
      standup.update!(organizer_name: "Pat", organizer_email: "pat@example.com",
        attendees: [ { "name" => "Sam", "email" => "sam@example.com", "status" => "accepted", "role" => "req-participant" } ])

      get tool_calendar_event_path(@tool, standup), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal [ "Standup", "Quick sync", "2030-01-07T09:30:00.000+01:00" ], body.values_at("summary", "description", "starts_at")
      assert_equal [ true, false ], body.values_at("recurring", "occurrence")
      assert_equal "Daily, 5 times", body["recurrence"]
      assert_equal({ "name" => "Pat", "email" => "pat@example.com" }, body["organizer"])
      assert_equal [ { "name" => "Sam", "email" => "sam@example.com", "status" => "accepted" } ], body["attendees"]
      assert_equal "confirmed", body["status"]
    end

    test "create adds an event in the user's time zone, pushes it and notifies collaborators" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")

      assert_difference -> { user_two.notifications.count }, 1 do
        post tool_calendar_events_path(@tool), headers: @headers, as: :json, params: {
          calendars_event: { calendar_id: @work.id, summary: "Dentist", location: "Main Street 1", description: "Bring the form",
                             start_time: "2030-01-08 14:00", end_time: "2030-01-08 15:00" }
        }
      end

      assert_response :created
      body = response.parsed_body
      event = ::Calendars::Event.find(body["id"])
      assert_equal "Work", body.dig("calendar", "name")
      assert_equal [ "Dentist", "Main Street 1", "Bring the form" ], body.values_at("summary", "location", "description")
      assert_equal "2030-01-08T14:00:00.000+01:00", body["starts_at"]
      assert_equal Time.find_zone("Amsterdam").local(2030, 1, 8, 14), event.starts_at
      assert_equal @user, event.created_by
      assert_enqueued_with job: PushEventJob, args: [ event.id, :create ]
    end

    test "create defaults to the default calendar and builds recurrence" do
      post tool_calendar_events_path(@tool), headers: @headers, as: :json, params: {
        calendars_event: { summary: "Rent", start_time: "2030-01-15 09:00", end_time: "2030-01-15 09:15",
                           recurrence_frequency: "monthly", recurrence_end_type: "count", recurrence_count: 3 }
      }

      assert_response :created
      body = response.parsed_body
      assert_equal @personal.id, body.dig("calendar", "id")
      assert_equal "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3", body["rrule"]
      assert_equal "Monthly on day 15, 3 times", body["recurrence"]

      get tool_calendar_path(@tool, start_date: "2030-01-01", end_date: "2030-03-31"), headers: @headers

      rent = response.parsed_body["events"].select { |event| event["summary"] == "Rent" }
      assert_equal %w[2030-01-15 2030-02-15 2030-03-15], rent.map { |event| event["starts_at"][0, 10] }
    end

    test "create without a summary returns errors" do
      assert_no_enqueued_jobs only: PushEventJob do
        post tool_calendar_events_path(@tool), headers: @headers, as: :json,
          params: { calendars_event: { summary: "", start_time: "2030-01-08 14:00", end_time: "2030-01-08 15:00" } }
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Title can't be blank"
    end

    test "create refuses read-only and disabled calendars" do
      @work.update!(read_only: true)

      assert_no_difference -> { ::Calendars::Event.count } do
        post tool_calendar_events_path(@tool), headers: @headers, as: :json,
          params: { calendars_event: { calendar_id: @work.id, summary: "Nope", start_time: "2030-01-08 14:00", end_time: "2030-01-08 15:00" } }
        assert_response :unprocessable_entity
        assert_equal [ "Calendar is read-only" ], response.parsed_body["errors"]

        post tool_calendar_events_path(@tool), headers: @headers, as: :json,
          params: { calendars_event: { calendar_id: calendars_calendars(:disabled_calendar).id, summary: "Nope", start_time: "2030-01-08 14:00", end_time: "2030-01-08 15:00" } }
        assert_response :unprocessable_entity
        assert_equal [ "Calendar is disabled" ], response.parsed_body["errors"]
      end

      assert_no_enqueued_jobs only: PushEventJob
    end

    test "update changes the event and pushes the change" do
      event = create_event(@personal, "Dentist", "2030-01-08 14:00", "2030-01-08 15:00")

      patch tool_calendar_event_path(@tool, event), headers: @headers, as: :json,
        params: { calendars_event: { summary: "Dentist (moved)", start_time: "2030-01-09T10:00:00+01:00", end_time: "2030-01-09 11:30", calendar_id: @work.id } }

      assert_response :success
      body = response.parsed_body
      assert_equal [ "Dentist (moved)", "2030-01-09T10:00:00.000+01:00", "2030-01-09T11:30:00.000+01:00" ], body.values_at("summary", "starts_at", "ends_at")
      assert_equal "Work", body.dig("calendar", "name")
      assert_equal @work, event.reload.calendar
      assert_enqueued_with job: PushEventJob, args: [ event.id, :move ]
    end

    test "update refuses to move an event to a read-only calendar" do
      event = create_event(@personal, "Dentist", "2030-01-08 14:00", "2030-01-08 15:00")
      @work.update!(read_only: true)

      patch tool_calendar_event_path(@tool, event), headers: @headers, as: :json,
        params: { calendars_event: { summary: "Moved", calendar_id: @work.id } }

      assert_response :unprocessable_entity
      assert_equal [ "Calendar is read-only" ], response.parsed_body["errors"]
      assert_equal [ @personal, "Dentist" ], [ event.reload.calendar, event.summary ]
    end

    test "updating the start of a recurring event moves the whole series" do
      standup = create_event(@personal, "Standup", "2030-01-07 09:30", "2030-01-07 09:45",
        recurrence_frequency: "weekly", recurrence_days_of_week: %w[MO WE FR], recurrence_end_type: "never")

      patch tool_calendar_event_path(@tool, standup), headers: @headers, as: :json,
        params: { calendars_event: { start_time: "2030-01-09 10:00", end_time: "2030-01-09 10:15" } }
      assert_response :success
      assert_equal "FREQ=WEEKLY;BYDAY=MO,WE,FR", response.parsed_body["rrule"]

      get tool_calendar_path(@tool, start_date: "2030-01-07", end_date: "2030-01-13"), headers: @headers
      assert_equal %w[2030-01-09T10:00:00.000+01:00 2030-01-11T10:00:00.000+01:00],
        response.parsed_body["events"].map { |event| event["starts_at"] }

      patch tool_calendar_event_path(@tool, standup), headers: @headers, as: :json,
        params: { calendars_event: { recurrence_end_type: "count", recurrence_count: 2 } }
      assert_equal "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=2", response.parsed_body["rrule"]

      patch tool_calendar_event_path(@tool, standup), headers: @headers, as: :json,
        params: { calendars_event: { summary: "Daily standup" } }
      assert_equal [ "Daily standup", "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=2" ], response.parsed_body.values_at("summary", "rrule")

      patch tool_calendar_event_path(@tool, standup), headers: @headers, as: :json,
        params: { calendars_event: { recurrence_frequency: "none" } }
      assert_equal [ false, nil ], response.parsed_body.values_at("recurring", "rrule")
    end

    test "destroy returns no content and deletes the event on the server" do
      event = calendars_events(:meeting)

      delete tool_calendar_event_path(@tool, event), headers: @headers, as: :json

      assert_response :no_content
      assert_not ::Calendars::Event.exists?(event.id)
      assert_enqueued_with job: DeleteCalendarEventJob,
        args: [ { remote_href: event.remote_href, etag: event.etag, calendar_id: event.calendar_id, uid: event.uid } ]
    end

    test "sync starts a sync and reports its status" do
      assert_enqueued_with job: SyncCalendarsJob, args: [ calendars_accounts(:icloud_account).id, { discover: true } ] do
        post tool_calendar_sync_path(@tool), headers: @headers, as: :json
      end

      assert_response :created
      assert_equal "syncing", response.parsed_body["status"]

      get tool_calendar_sync_path(@tool), headers: @headers

      assert_response :success
      assert_equal "syncing", response.parsed_body["status"]
    end

    test "a calendar tool without an account answers 404" do
      tool = Tool.create!(name: "Unconnected", tool_type: tool_types(:calendar), owner: @user)

      get tool_calendar_path(tool), headers: @headers
      assert_response :not_found
      assert_equal "Calendar account not configured", response.parsed_body["error"]

      post tool_calendar_events_path(tool), headers: @headers, as: :json, params: { calendars_event: { summary: "Nope" } }
      assert_response :not_found

      assert_no_enqueued_jobs do
        post tool_calendar_sync_path(tool), headers: @headers, as: :json
      end
      assert_response :not_found
      assert_equal "Calendar account not configured", response.parsed_body["error"]
    end

    test "read-only tokens can read but not change the calendar" do
      headers = api_headers(@user, permission: "read")
      event = calendars_events(:meeting)

      get tool_calendar_path(@tool), headers: headers
      assert_response :success
      get tool_calendar_event_path(@tool, event), headers: headers
      assert_response :success

      post tool_calendar_events_path(@tool), headers: headers, as: :json,
        params: { calendars_event: { summary: "Nope", start_time: "2030-01-08 14:00", end_time: "2030-01-08 15:00" } }
      assert_response :forbidden
      delete tool_calendar_event_path(@tool, event), headers: headers, as: :json
      assert_response :forbidden
      post tool_calendar_sync_path(@tool), headers: headers, as: :json
      assert_response :forbidden

      assert ::Calendars::Event.exists?(event.id)
      assert_no_enqueued_jobs
    end

    test "events and calendars of other tools are out of reach" do
      other_calendar = calendars_accounts(:pending_account).calendars.create!(name: "Theirs", remote_id: "/theirs/")
      theirs = create_event(other_calendar, "Their event", "2030-01-08 14:00", "2030-01-08 15:00")
      mine = create_event(@personal, "My event", "2030-01-08 14:00", "2030-01-08 15:00")

      get tool_calendar_path(tools(:other_calendar)), headers: @headers
      assert_response :forbidden

      get tool_calendar_event_path(@tool, theirs), headers: @headers
      assert_response :not_found
      patch tool_calendar_event_path(@tool, theirs), headers: @headers, as: :json, params: { calendars_event: { summary: "Mine now" } }
      assert_response :not_found
      delete tool_calendar_event_path(@tool, theirs), headers: @headers, as: :json
      assert_response :not_found

      patch tool_calendar_event_path(@tool, mine), headers: @headers, as: :json, params: { calendars_event: { calendar_id: other_calendar.id } }
      assert_response :not_found
      assert_equal @personal, mine.reload.calendar

      post tool_calendar_events_path(@tool), headers: @headers, as: :json,
        params: { calendars_event: { calendar_id: other_calendar.id, summary: "Sneaky", start_time: "2030-01-08 14:00", end_time: "2030-01-08 15:00" } }
      assert_response :not_found

      assert_equal [ "Their event" ], other_calendar.events.pluck(:summary)
      assert_no_enqueued_jobs
    end

    test "tokens can't reach calendar accounts or invites" do
      get new_tool_calendar_account_path(@tool), headers: @headers
      assert_response :forbidden
      get edit_tool_calendar_account_path(@tool), headers: @headers
      assert_response :forbidden

      patch tool_calendar_account_path(@tool), headers: @headers, as: :json,
        params: { calendars_account: { username: "attacker@example.com", password: "secret" } }
      assert_response :forbidden
      assert_equal "This action isn't available to access tokens", response.parsed_body["error"]
      assert_equal "user@icloud.com", calendars_accounts(:icloud_account).reload.username

      post tool_calendar_invites_path(@tool), headers: @headers, as: :json, params: { invite_id: 1 }
      assert_response :forbidden
      delete tool_calendar_invite_path(@tool, 1), headers: @headers, as: :json
      assert_response :forbidden
    end

    private

    # Creates an event with times given in the user's time zone.
    def create_event(calendar, summary, starts_at, ends_at, **attributes)
      Time.use_zone(@user.timezone) do
        calendar.events.create!(uid: "#{SecureRandom.uuid}@test", summary: summary, created_by: @user,
          starts_at: Time.zone.parse(starts_at), ends_at: Time.zone.parse(ends_at), **attributes)
      end
    end
  end
end

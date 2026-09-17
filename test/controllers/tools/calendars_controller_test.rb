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

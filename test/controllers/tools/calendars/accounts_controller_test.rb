# frozen_string_literal: true

require "test_helper"

module Tools
  module Calendars
    class AccountsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = Tool.create!(name: "Team Calendar", tool_type: tool_types(:calendar), owner: users(:one))
      end

      test "connecting a CalDAV account syncs it, looking for its calendars" do
        assert_enqueued_with job: SyncCalendarsJob, args: ->(args) { args.second == { discover: true } } do
          post tool_calendar_account_path(@tool), params: {
            calendars_account: { provider: "custom", caldav_url: "https://caldav.example.com/", username: "me", password: "secret" }
          }
        end

        assert_redirected_to tool_calendar_path(@tool)
        assert_not @tool.reload.calendar_account.local?
      end

      test "creating a local account adds a default calendar named after the tool" do
        post tool_calendar_account_path(@tool), params: { calendars_account: { provider: "local" } }

        assert_redirected_to tool_calendar_path(@tool)
        account = @tool.reload.calendar_account
        assert account.local?
        calendar = account.calendars.sole
        assert_equal [ "Team Calendar", true, true, nil ], [ calendar.name, calendar.is_default?, calendar.enabled?, calendar.remote_id ]
      end
    end
  end
end

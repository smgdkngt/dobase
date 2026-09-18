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

      test "the setup and settings labels point at their fields" do
        get new_tool_calendar_account_path(@tool)
        assert_labels_match_fields %w[caldav_url username password]

        get edit_tool_calendar_account_path(calendars_accounts(:icloud_account).tool)
        assert_labels_match_fields %w[caldav_url username password]
      end

      test "there is no connection test endpoint" do
        post "/tools/#{@tool.id}/calendar/account/test_connection"

        assert_response :not_found
      end

      test "the account settings have no delete button that would submit them instead" do
        tool = calendars_accounts(:icloud_account).tool

        get edit_tool_calendar_account_path(tool)

        assert_response :success
        assert_select "form[action=?]", tool_calendar_account_path(tool) do
          assert_select "input[name='_method']", count: 1
          assert_select "button", text: "Save Changes"
          assert_select "button", text: "Delete Account", count: 0
        end
      end

      test "an account isn't saved without a CalDAV address" do
        account = calendars_accounts(:icloud_account)

        patch tool_calendar_account_path(account.tool), params: { calendars_account: { caldav_url: " " } }

        assert_response :unprocessable_entity
        assert_select ".flash-error", text: "CalDAV URL can't be blank"
        assert_equal "https://caldav.icloud.com/", account.reload.caldav_url
      end

      test "creating a local account adds a default calendar named after the tool" do
        post tool_calendar_account_path(@tool), params: { calendars_account: { provider: "local" } }

        assert_redirected_to tool_calendar_path(@tool)
        account = @tool.reload.calendar_account
        assert account.local?
        calendar = account.calendars.sole
        assert_equal [ "Team Calendar", true, true, nil ], [ calendar.name, calendar.is_default?, calendar.enabled?, calendar.remote_id ]
      end

      private

      def assert_labels_match_fields(fields)
        fields.each do |field|
          assert_select "label.label[for=calendars_account_#{field}]", count: 1
          assert_select "input#calendars_account_#{field}", count: 1
        end
        css_select("form[action$='/calendar/account'] label[for]").each do |label|
          assert_select "##{label['for']}", 1
        end
      end
    end
  end
end

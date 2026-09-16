# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class SyncCalendarsJobTest < ActiveJob::TestCase
  EMPTY_MULTISTATUS = %(<?xml version="1.0" encoding="UTF-8"?><d:multistatus xmlns:d="DAV:"></d:multistatus>)

  setup do
    WebMock.disable_net_connect!
    tool = Tool.create!(name: "Work Calendar", tool_type: tool_types(:calendar), owner: users(:one))
    @account = Calendars::Account.create!(tool: tool, provider: "custom", caldav_url: "https://caldav.example.com/", username: "me", password: "secret")

    stub_request(:any, /caldav\.example\.com/).to_return(status: 207, body: EMPTY_MULTISTATUS)
    @discovery = stub_request(:propfind, "https://caldav.example.com/")
      .with(body: /current-user-principal/)
      .to_return(status: 207, body: EMPTY_MULTISTATUS)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "looks for the calendars of an account that has none yet" do
    SyncCalendarsJob.perform_now(@account.id)

    assert_requested @discovery
  end

  test "a recurring sync of an account with calendars doesn't look for new ones" do
    add_calendar

    SyncCalendarsJob.perform_now(@account.id)

    assert_not_requested @discovery
  end

  test "a sync someone asked for looks for new calendars" do
    add_calendar

    SyncCalendarsJob.perform_now(@account.id, discover: true)

    assert_requested @discovery
  end

  private

  def add_calendar
    @account.calendars.create!(name: "Work", remote_id: "/cal/work/", remote_url: "https://caldav.example.com/cal/work/")
  end
end

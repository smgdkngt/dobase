# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class SyncCalendarsJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  EMPTY_MULTISTATUS = %(<?xml version="1.0" encoding="UTF-8"?><d:multistatus xmlns:d="DAV:"></d:multistatus>)
  ONE_EVENT = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:href>/cal/work/standup.ics</d:href>
        <d:propstat>
          <d:prop>
            <d:getetag>"etag-standup"</d:getetag>
            <c:calendar-data>BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:standup@example.com
    DTSTART:20300108T140000Z
    DTEND:20300108T150000Z
    SUMMARY:Standup
    END:VEVENT
    END:VCALENDAR
    </c:calendar-data>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
  XML

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

  test "a sync the server turns down for the password says so and isn't marked synced" do
    add_calendar
    @account.update!(last_synced_at: nil)
    stub_request(:any, /caldav\.example\.com/).to_return(status: 401)

    SyncCalendarsJob.perform_now(@account.id)

    @account.reload
    assert_equal [ "error", "The calendar server didn't accept the username or password" ], [ @account.sync_status, @account.sync_error ]
    assert @account.authentication_failed?
    assert_nil @account.last_synced_at
  end

  test "a wrong password while looking for calendars isn't reported as a wrong address" do
    stub_request(:any, /caldav\.example\.com/).to_return(status: 401)

    SyncCalendarsJob.perform_now(@account.id, discover: true)

    assert @account.reload.authentication_failed?
  end

  test "a sync in which the server refused every calendar isn't marked synced" do
    add_calendar
    @account.update!(last_synced_at: nil)
    stub_request(:any, /caldav\.example\.com\/cal\/work/).to_return(status: 503)

    SyncCalendarsJob.perform_now(@account.id)

    @account.reload
    assert_equal "error", @account.sync_status
    assert_match "503", @account.sync_error
    assert_not @account.authentication_failed?
    assert_nil @account.last_synced_at
  end

  test "one calendar the server refuses doesn't stop the others from syncing" do
    add_calendar
    @account.calendars.create!(name: "Shared", remote_id: "/cal/shared/", remote_url: "https://caldav.example.com/cal/shared/")
    stub_request(:any, /caldav\.example\.com\/cal\/shared/).to_return(status: 403)

    SyncCalendarsJob.perform_now(@account.id)

    assert_equal "synced", @account.reload.sync_status
  end

  test "a sync that brings an event says so to the pages that have the calendar open, and one that brings nothing new doesn't" do
    add_calendar
    stub_request(:report, "https://caldav.example.com/cal/work/").to_return(status: 207, body: ONE_EVENT)
    pages = PresenceChannel.broadcasting_for(@account.tool)

    assert_broadcast_on(pages, type: "changed", tool_id: @account.tool.id) do
      SyncCalendarsJob.perform_now(@account.id)
    end
    assert_equal [ "Standup" ], @account.events.pluck(:summary)

    assert_no_broadcasts(pages) { SyncCalendarsJob.perform_now(@account.id) }
  end

  test "the scheduled sync skips an account whose password was turned down, until its settings change or someone asks for a sync" do
    @account.mark_sync_error!(Calendars::Account::AUTHENTICATION_FAILED)

    SyncAllCalendarsJob.perform_now
    assert_not_includes enqueued_jobs.map { |job| job["arguments"].first }, @account.id

    # The sync button and new settings mark the account as syncing first
    @account.mark_syncing!
    assert_enqueued_with(job: SyncCalendarsJob, args: [ @account.id ]) { SyncAllCalendarsJob.perform_now }
  end

  private

  def add_calendar
    @account.calendars.create!(name: "Work", remote_id: "/cal/work/", remote_url: "https://caldav.example.com/cal/work/")
  end
end

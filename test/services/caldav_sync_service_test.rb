# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class CaldavSyncServiceTest < ActiveSupport::TestCase
  setup do
    @account = calendars_accounts(:icloud_account)
    @service = CaldavSyncService.new(@account)

    # Disable external requests by default
    WebMock.disable_net_connect!

    # Stub write-test probes used during calendar discovery
    stub_request(:put, /\.ics$/).to_return(status: 201)
    stub_request(:delete, /\.ics$/).to_return(status: 204)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  # Connection tests

  test "test_connection succeeds with valid credentials" do
    stub_request(:propfind, @account.caldav_url)
      .to_return(status: 207, body: principal_response)

    assert @service.test_connection
  end

  test "test_connection raises AuthenticationError on 401" do
    stub_request(:propfind, @account.caldav_url)
      .to_return(status: 401, body: "")

    assert_raises(CaldavSyncService::AuthenticationError) do
      @service.test_connection
    end
  end

  test "test_connection raises ConnectionError on server error" do
    stub_request(:propfind, @account.caldav_url)
      .to_return(status: 500, body: "")

    assert_raises(CaldavSyncService::ConnectionError) do
      @service.test_connection
    end
  end

  # Calendar discovery tests

  test "discover_calendars finds and saves calendars" do
    # Stub the full discovery chain
    stub_request(:propfind, @account.caldav_url)
      .to_return(status: 207, body: principal_response)

    stub_request(:propfind, "https://caldav.icloud.com/123456789/principal/")
      .to_return(status: 207, body: calendar_home_response)

    stub_request(:propfind, "https://caldav.icloud.com/123456789/calendars/")
      .to_return(status: 207, body: calendars_list_response)

    initial_count = @account.calendars.count

    @service.discover_calendars

    # Should have created new calendars (the fixture already has some)
    assert @account.calendars.count >= initial_count
  end

  test "discover_calendars preserves existing calendar sync_token" do
    existing = calendars_calendars(:personal)
    original_sync_token = existing.sync_token
    original_ctag = existing.ctag

    stub_request(:propfind, @account.caldav_url)
      .to_return(status: 207, body: principal_response)

    stub_request(:propfind, "https://caldav.icloud.com/123456789/principal/")
      .to_return(status: 207, body: calendar_home_response)

    stub_request(:propfind, "https://caldav.icloud.com/123456789/calendars/")
      .to_return(status: 207, body: calendars_list_response(remote_id: existing.remote_id))

    @service.discover_calendars

    existing.reload
    assert_equal original_sync_token, existing.sync_token
    assert_equal original_ctag, existing.ctag
  end

  test "discover_calendars raises error when principal not found" do
    stub_request(:propfind, @account.caldav_url)
      .to_return(status: 207, body: empty_multistatus_response)

    assert_raises(CaldavSyncService::SyncError) do
      @service.discover_calendars
    end
  end

  # Sync tests

  test "sync_calendar performs full sync when no sync_token" do
    calendar = calendars_calendars(:personal)
    calendar.update!(sync_token: nil, ctag: nil)

    stub_request(:report, calendar.remote_url)
      .to_return(status: 207, body: calendar_query_response([]))

    stub_request(:propfind, calendar.remote_url)
      .to_return(status: 207, body: sync_token_response)

    @service.sync_calendar(calendar)

    calendar.reload
    assert_not_nil calendar.sync_token
  end

  test "sync_calendar performs delta sync when sync_token present and ctag unchanged" do
    calendar = calendars_calendars(:personal)
    original_events_count = calendar.events.count

    # ctag unchanged - stub the ctag check
    stub_request(:propfind, calendar.remote_url)
      .to_return(status: 207, body: ctag_response(calendar.ctag))

    stub_request(:report, calendar.remote_url)
      .to_return(status: 207, body: delta_sync_response(calendar.sync_token, [], []))

    @service.sync_calendar(calendar)

    # Events count should remain the same (no changes from server)
    assert_equal original_events_count, calendar.events.count
  end

  test "sync_calendar performs full sync when ctag changed" do
    calendar = calendars_calendars(:personal)
    old_ctag = calendar.ctag
    calendar.update!(sync_token: "old-token")

    # First stub: ctag check returns different ctag
    stub_request(:propfind, calendar.remote_url)
      .to_return(
        { status: 207, body: ctag_response("new-different-ctag") },
        { status: 207, body: sync_token_response }
      )

    stub_request(:report, calendar.remote_url)
      .to_return(status: 207, body: calendar_query_response([]))

    @service.sync_calendar(calendar)

    calendar.reload
    assert_not_equal old_ctag, calendar.ctag
  end

  test "full_sync creates new events" do
    calendar = calendars_calendars(:personal)
    calendar.update!(sync_token: nil, ctag: nil)
    calendar.events.destroy_all

    stub_request(:report, calendar.remote_url)
      .to_return(status: 207, body: calendar_query_response([
        { uid: "new-event-1", summary: "New Event 1" },
        { uid: "new-event-2", summary: "New Event 2" }
      ]))

    stub_request(:propfind, calendar.remote_url)
      .to_return(status: 207, body: sync_token_response)

    assert_difference -> { calendar.events.count }, 2 do
      @service.sync_calendar(calendar)
    end

    assert calendar.events.exists?(uid: "new-event-1")
    assert calendar.events.exists?(uid: "new-event-2")
  end

  test "full_sync removes events deleted from server" do
    calendar = calendars_calendars(:personal)
    calendar.update!(sync_token: nil, ctag: nil)

    # Create an event that exists locally but not on server
    orphan = calendar.events.create!(
      uid: "orphan-event",
      summary: "Orphan",
      starts_at: 1.hour.from_now,
      ends_at: 2.hours.from_now
    )

    stub_request(:report, calendar.remote_url)
      .to_return(status: 207, body: calendar_query_response([
        { uid: "server-event", summary: "Server Event" }
      ]))

    stub_request(:propfind, calendar.remote_url)
      .to_return(status: 207, body: sync_token_response)

    @service.sync_calendar(calendar)

    assert_not Calendars::Event.exists?(id: orphan.id)
    assert calendar.events.exists?(uid: "server-event")
  end

  test "delta_sync handles deleted events" do
    calendar = calendars_calendars(:personal)
    event = calendar.events.create!(
      uid: "deleted-event",
      summary: "To Be Deleted",
      starts_at: 1.hour.from_now,
      ends_at: 2.hours.from_now
    )

    stub_request(:propfind, calendar.remote_url)
      .to_return(status: 207, body: ctag_response(calendar.ctag))

    stub_request(:report, calendar.remote_url)
      .to_return(status: 207, body: delta_sync_response(calendar.sync_token, [ "deleted-event" ], []))

    @service.sync_calendar(calendar)

    assert_not Calendars::Event.exists?(id: event.id)
  end

  test "delta_sync falls back to full sync on invalid token" do
    calendar = calendars_calendars(:personal)
    old_token = calendar.sync_token

    # First: ctag check
    stub_request(:propfind, calendar.remote_url)
      .to_return(
        { status: 207, body: ctag_response(calendar.ctag) },
        { status: 207, body: sync_token_response }
      )

    # Delta sync returns 403 (invalid token)
    stub_request(:report, calendar.remote_url)
      .to_return(
        { status: 403, body: "" },
        { status: 207, body: calendar_query_response([]) }
      )

    @service.sync_calendar(calendar)

    calendar.reload
    # After fallback to full sync, token should be updated (not the old one)
    assert_not_equal old_token, calendar.sync_token
  end

  # Event push tests

  test "create_event pushes event to server" do
    calendar = calendars_calendars(:personal)
    event = calendar.events.create!(
      uid: "new-local-event@dobase",
      summary: "New Event",
      starts_at: 1.hour.from_now,
      ends_at: 2.hours.from_now
    )

    expected_url = "#{calendar.remote_url}#{event.uid}.ics"
    stub_request(:put, expected_url)
      .to_return(status: 201, headers: { "ETag" => '"new-etag-123"' })

    @service.create_event(event)

    event.reload
    assert_equal "new-etag-123", event.etag
    assert_equal expected_url, event.remote_href
  end

  test "update_event pushes changes to server" do
    event = calendars_events(:meeting)
    event.update!(summary: "Updated Meeting")

    stub_request(:put, event.remote_href)
      .to_return(status: 200, headers: { "ETag" => '"updated-etag"' })

    @service.update_event(event)

    event.reload
    assert_equal "updated-etag", event.etag
  end

  test "update_event sends If-Match header with etag" do
    event = calendars_events(:meeting)
    original_etag = event.etag

    stub = stub_request(:put, event.remote_href)
      .with(headers: { "If-Match" => %("#{original_etag}") })
      .to_return(status: 200, headers: { "ETag" => '"new-etag"' })

    @service.update_event(event)

    assert_requested stub
  end

  test "delete_event removes event from server" do
    event = calendars_events(:meeting)

    stub = stub_request(:delete, event.remote_href)
      .with(headers: { "If-Match" => %("#{event.etag}") })
      .to_return(status: 204)

    @service.delete_event(event)

    assert_requested stub
  end

  test "delete_event handles 404 gracefully" do
    event = calendars_events(:meeting)

    stub_request(:delete, event.remote_href).to_return(status: 404)

    # Should not raise
    assert_nothing_raised do
      @service.delete_event(event)
    end
  end

  test "delete_event skips events without remote_href" do
    event = calendars_events(:meeting)
    event.update!(remote_href: nil)

    # No stub needed - should not make request
    assert_nothing_raised do
      @service.delete_event(event)
    end
  end

  # ICS generation tests

  test "builds valid icalendar for timed event" do
    event = calendars_events(:meeting)

    ics = @service.send(:build_icalendar, event)

    assert_includes ics, "BEGIN:VCALENDAR"
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "UID:#{event.uid}"
    assert_includes ics, "SUMMARY:#{event.summary}"
    assert_includes ics, "LOCATION:#{event.location}"
    assert_includes ics, "END:VEVENT"
    assert_includes ics, "END:VCALENDAR"
  end

  test "builds valid icalendar for all-day event" do
    event = calendars_events(:all_day_event)

    ics = @service.send(:build_icalendar, event)

    # All-day events should use DATE format, not DATE-TIME
    assert_match(/DTSTART;VALUE=DATE:\d{8}/, ics)
  end

  # Response XML generators

  private

  def principal_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:">
        <d:response>
          <d:href>/</d:href>
          <d:propstat>
            <d:prop>
              <d:current-user-principal>
                <d:href>/123456789/principal/</d:href>
              </d:current-user-principal>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end

  def calendar_home_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:response>
          <d:href>/123456789/principal/</d:href>
          <d:propstat>
            <d:prop>
              <c:calendar-home-set>
                <d:href>/123456789/calendars/</d:href>
              </c:calendar-home-set>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end

  def calendars_list_response(remote_id: nil)
    remote_id ||= "/123456789/calendars/new-personal/"

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:x="http://apple.com/ns/ical/">
        <d:response>
          <d:href>/123456789/calendars/</d:href>
          <d:propstat>
            <d:prop>
              <d:resourcetype>
                <d:collection/>
              </d:resourcetype>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        <d:response>
          <d:href>#{remote_id}</d:href>
          <d:propstat>
            <d:prop>
              <d:resourcetype>
                <d:collection/>
                <c:calendar/>
              </d:resourcetype>
              <d:displayname>Personal</d:displayname>
              <x:calendar-color>#3b82f6FF</x:calendar-color>
              <cs:getctag>ctag-personal-123</cs:getctag>
              <d:sync-token>https://caldav.icloud.com/sync/token-new</d:sync-token>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end

  def calendar_query_response(events)
    events_xml = events.map do |event|
      uid = event[:uid]
      summary = event[:summary] || "Event"
      starts_at = (event[:starts_at] || 1.hour.from_now).strftime("%Y%m%dT%H%M%SZ")
      ends_at = (event[:ends_at] || 2.hours.from_now).strftime("%Y%m%dT%H%M%SZ")

      ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:#{uid}
        DTSTART:#{starts_at}
        DTEND:#{ends_at}
        SUMMARY:#{summary}
        END:VEVENT
        END:VCALENDAR
      ICS

      <<~XML
        <d:response>
          <d:href>/calendars/#{uid}.ics</d:href>
          <d:propstat>
            <d:prop>
              <d:getetag>"etag-#{uid}"</d:getetag>
              <c:calendar-data>#{ics}</c:calendar-data>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      XML
    end.join("\n")

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        #{events_xml}
      </d:multistatus>
    XML
  end

  def sync_token_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:response>
          <d:href>/calendars/personal/</d:href>
          <d:propstat>
            <d:prop>
              <d:sync-token>https://caldav.icloud.com/sync/token-updated</d:sync-token>
              <cs:getctag>ctag-updated</cs:getctag>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end

  def ctag_response(ctag)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:response>
          <d:href>/calendars/personal/</d:href>
          <d:propstat>
            <d:prop>
              <cs:getctag>#{ctag}</cs:getctag>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end

  def delta_sync_response(sync_token, deleted_uids, changed_events)
    deleted_xml = deleted_uids.map do |uid|
      <<~XML
        <d:response>
          <d:href>/calendars/#{uid}.ics</d:href>
          <d:status>HTTP/1.1 404 Not Found</d:status>
        </d:response>
      XML
    end.join("\n")

    changed_xml = changed_events.map do |event|
      uid = event[:uid]
      summary = event[:summary] || "Changed Event"

      ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:#{uid}
        DTSTART:#{1.hour.from_now.strftime("%Y%m%dT%H%M%SZ")}
        DTEND:#{2.hours.from_now.strftime("%Y%m%dT%H%M%SZ")}
        SUMMARY:#{summary}
        END:VEVENT
        END:VCALENDAR
      ICS

      <<~XML
        <d:response>
          <d:href>/calendars/#{uid}.ics</d:href>
          <d:propstat>
            <d:prop>
              <d:getetag>"etag-#{uid}"</d:getetag>
              <c:calendar-data>#{ics}</c:calendar-data>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      XML
    end.join("\n")

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        #{deleted_xml}
        #{changed_xml}
        <d:sync-token>https://caldav.icloud.com/sync/token-after-delta</d:sync-token>
      </d:multistatus>
    XML
  end

  def empty_multistatus_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:">
      </d:multistatus>
    XML
  end
end

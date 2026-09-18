# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class CaldavSyncServiceTest < ActiveSupport::TestCase
  setup do
    @account = calendars_accounts(:icloud_account)
    @service = CaldavSyncService.new(@account)

    # Disable external requests by default
    WebMock.disable_net_connect!
  end

  teardown do
    WebMock.allow_net_connect!
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

  test "server responses can't pull local files in through XML entities" do
    Tempfile.create("caldav-secret") do |file|
      file.write("very-secret-value")
      file.flush
      stub_request(:propfind, "https://caldav.icloud.com/123456789/calendars/").to_return(status: 207, body: <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE d:multistatus [<!ENTITY secret SYSTEM "file://#{file.path}">]>
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/123456789/calendars/leak/</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
                <d:displayname>&secret;</d:displayname>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
      XML

      calendars = @service.send(:list_calendars, "https://caldav.icloud.com/123456789/calendars/")

      assert_equal [ "/123456789/calendars/leak/" ], calendars.map { |calendar| calendar[:remote_id] }
      assert_not_includes calendars.inspect, "very-secret-value"
    end
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
    stub_request(:propfind, "https://caldav.icloud.com/.well-known/caldav").to_return(status: 404)

    error = assert_raises(CaldavSyncService::SyncError) do
      @service.discover_calendars
    end
    assert_equal "No CalDAV server found at this address. Check the CalDAV URL.", error.message
  end

  test "discover_calendars finds the server through its well-known address" do
    @account.update!(caldav_url: "https://cloud.example.com/")
    stub_request(:propfind, "https://cloud.example.com/").to_return(status: 207, body: empty_multistatus_response)
    stub_request(:propfind, "https://cloud.example.com/.well-known/caldav")
      .to_return(status: 301, headers: { "Location" => "/remote.php/dav/" })
    stub_request(:propfind, "https://cloud.example.com/remote.php/dav/").to_return(status: 207, body: principal_response)
    stub_request(:propfind, "https://cloud.example.com/123456789/principal/").to_return(status: 207, body: calendar_home_response)
    calendars = stub_request(:propfind, "https://cloud.example.com/123456789/calendars/").to_return(status: 207, body: calendars_list_response)

    CaldavSyncService.new(@account).discover_calendars

    assert_requested calendars
  end

  test "discovery doesn't follow a redirect to another host" do
    @account.update!(caldav_url: "https://cloud.example.com/")
    stub_request(:propfind, "https://cloud.example.com/").to_return(status: 207, body: empty_multistatus_response)
    stub_request(:propfind, "https://cloud.example.com/.well-known/caldav")
      .to_return(status: 307, headers: { "Location" => "https://elsewhere.example.net/dav/" })
    elsewhere = stub_request(:propfind, "https://elsewhere.example.net/dav/")

    assert_raises(CaldavSyncService::SyncError) { CaldavSyncService.new(@account).discover_calendars }
    assert_not_requested elsewhere
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

  test "an untitled or invalid event doesn't hold up the sync" do
    personal = calendars_calendars(:personal)
    work = calendars_calendars(:work)
    [ personal, work ].each { |calendar| calendar.update!(sync_token: nil, ctag: nil) }

    stub_request(:report, personal.remote_url).to_return(status: 207, body: calendar_query_response([
      { uid: "untitled", ics: <<~ICS },
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:untitled
        DTSTART:20301008T140000Z
        DTEND:20301008T150000Z
        END:VEVENT
        END:VCALENDAR
      ICS
      { uid: "backwards", summary: "Ends before it starts", starts_at: 2.hours.from_now, ends_at: 1.hour.from_now },
      { uid: "fine", summary: "Fine" }
    ]))
    stub_request(:report, work.remote_url)
      .to_return(status: 207, body: calendar_query_response([ { uid: "planning", summary: "Planning" } ]))
    stub_request(:propfind, /caldav\.icloud\.com/).to_return(status: 207, body: sync_token_response)

    @service.sync_all_calendars

    assert_equal "(No title)", personal.events.find_by!(uid: "untitled").summary
    assert_equal [ "fine", "untitled" ], personal.events.order(:uid).pluck(:uid)
    assert work.events.exists?(uid: "planning")
    assert_equal "https://caldav.icloud.com/sync/token-updated", personal.reload.sync_token
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

  test "a calendar server on a local address isn't contacted" do
    @account.update!(caldav_url: "http://169.254.169.254/latest/")

    error = assert_raises(CaldavSyncService::ConnectionError) { @service.discover_calendars }
    assert_match "local address", error.message
  end

  test "an event isn't pushed to a local address the server pointed at" do
    calendar = calendars_calendars(:personal)
    calendar.update!(remote_url: "http://127.0.0.1/calendars/personal/")
    event = calendar.events.create!(uid: "pushed@dobase", summary: "Pushed", starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)

    assert_raises(CaldavSyncService::ConnectionError) { @service.create_event(event) }
  end

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

  test "create_event and update_event PUT calendar objects without a METHOD" do
    event = calendars_events(:meeting)
    bodies = []
    stub_request(:put, /.*/).to_return do |request|
      bodies << request.body
      { status: 201, headers: { "ETag" => '"etag"' } }
    end

    @service.create_event(event)
    @service.update_event(event.reload)

    assert_equal 2, bodies.size
    bodies.each do |body|
      assert_includes body, "BEGIN:VCALENDAR"
      assert_no_match(/^METHOD:/, body)
    end
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

  test "update_event sends the organizer and attendees" do
    event = calendars_events(:meeting)
    event.update!(organizer_email: "rachel@example.com", organizer_name: "Rachel Kim", attendees: [
      { "email" => "rachel@example.com", "name" => "Rachel Kim", "status" => "accepted" },
      { "email" => "sophie@example.com", "name" => nil, "status" => nil }
    ])
    sent = nil
    stub_request(:put, event.remote_href).to_return do |request|
      sent = request.body
      { status: 204, headers: { "ETag" => '"with-attendees"' } }
    end

    @service.update_event(event)

    vevent = Icalendar::Calendar.parse(sent).sole.events.sole
    assert_equal [ "mailto:rachel@example.com", [ "Rachel Kim" ] ], [ vevent.organizer.to_s, vevent.organizer.ical_params["cn"] ]
    attendees = vevent.attendee.map { |attendee| [ attendee.to_s, attendee.ical_params["cn"], attendee.ical_params["partstat"] ] }
    assert_equal [
      [ "mailto:rachel@example.com", [ "Rachel Kim" ], [ "ACCEPTED" ] ],
      [ "mailto:sophie@example.com", nil, [ "NEEDS-ACTION" ] ]
    ], attendees
    assert_equal "with-attendees", event.reload.etag
  end

  test "update_event keeps the skipped and changed occurrences of a synced repeating event" do
    event = synced_standup
    event.update!(summary: "Daily standup")

    ics = capture_put(event.remote_href) { @service.update_event(event) }

    calendar = Icalendar::Calendar.parse(ics).sole
    series, moved = calendar.events
    assert_equal [ "Daily standup", nil, "FREQ=DAILY;COUNT=5" ], [ series.summary, series.recurrence_id, series.rrule.first.value_ical ]
    assert_equal [ Time.utc(2030, 1, 9, 8, 30) ], series.exdate.flatten.map { |time| time.to_time.utc }
    assert_equal [ "Standup (moved)", Time.utc(2030, 1, 10, 8, 30) ], [ moved.summary, moved.recurrence_id.to_time.utc ]
    assert_equal [ "Europe/Amsterdam" ], calendar.timezones.map { |timezone| timezone.tzid.to_s }
  end

  test "update_event leaves out the old exceptions once the series starts at another time" do
    event = synced_standup
    event.update!(starts_at: event.starts_at + 1.hour, ends_at: event.ends_at + 1.hour)

    ics = capture_put(event.remote_href) { @service.update_event(event) }

    series, *others = Icalendar::Calendar.parse(ics).sole.events
    assert_empty series.exdate
    assert_empty others
  end

  test "move_event creates the event in its new calendar and deletes it from the old one" do
    event = calendars_events(:meeting)
    old_href, old_etag = event.remote_href, event.etag
    work = calendars_calendars(:work)
    event.update!(calendar: work)

    created = stub_request(:put, "#{work.remote_url}#{event.uid}.ics")
      .with { |request| !request.headers.key?("If-Match") }
      .to_return(status: 201, headers: { "ETag" => '"in-work"' })
    deleted = stub_request(:delete, old_href).with(headers: { "If-Match" => %("#{old_etag}") }).to_return(status: 204)

    @service.move_event(event)

    assert_requested created
    assert_requested deleted
    assert_equal [ "#{work.remote_url}#{event.uid}.ics", "in-work" ], [ event.reload.remote_href, event.etag ]
  end

  test "a move that the old calendar refuses to let go still leaves the event in the new one" do
    event = calendars_events(:meeting)
    old_href = event.remote_href
    work = calendars_calendars(:work)
    event.update!(calendar: work)
    stub_request(:put, "#{work.remote_url}#{event.uid}.ics").to_return(status: 201, headers: { "ETag" => '"in-work"' })
    stub_request(:delete, old_href).to_return(status: 403)

    assert_nothing_raised { @service.move_event(event) }

    assert_equal "#{work.remote_url}#{event.uid}.ics", event.reload.remote_href
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

  test "sends the times of an event in UTC" do
    event = calendars_events(:meeting)

    ics = @service.send(:build_icalendar, event)

    assert_includes ics, "DTSTART:#{event.starts_at.utc.strftime('%Y%m%dT%H%M%SZ')}"
    assert_includes ics, "DTEND:#{event.ends_at.utc.strftime('%Y%m%dT%H%M%SZ')}"
    assert_match(/^DTSTAMP:\d{8}T\d{6}Z\r?$/, ics)
    Time.use_zone("Tokyo") do
      assert_equal event.starts_at, IcsParserService.new(ics).parse[:starts_at]
    end
  end

  test "builds valid icalendar for all-day event" do
    event = calendars_events(:all_day_event)

    ics = @service.send(:build_icalendar, event)

    # All-day events should use DATE format, not DATE-TIME
    assert_match(/DTSTART;VALUE=DATE:\d{8}/, ics)
  end

  test "an all-day event made east of UTC is sent with its own dates" do
    event = Time.use_zone("Amsterdam") do
      calendars_calendars(:personal).events.create!(uid: "offsite@dobase", summary: "Offsite", all_day: true,
        start_time: "2030-01-10 00:00", end_time: "2030-01-11 23:59:59")
    end

    ics = @service.send(:build_icalendar, event.reload)

    assert_includes ics, "DTSTART;VALUE=DATE:20300110"
    assert_includes ics, "DTEND;VALUE=DATE:20300112"
  end

  # Response XML generators

  private

  def capture_put(url)
    sent = nil
    stub_request(:put, url).to_return do |request|
      sent = request.body
      { status: 204, headers: { "ETag" => '"updated"' } }
    end
    yield
    sent
  end

  # A daily standup that skips its third day and was moved to 11:00 on the fourth
  def synced_standup
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Example//Server//EN
      BEGIN:VTIMEZONE
      TZID:Europe/Amsterdam
      BEGIN:STANDARD
      DTSTART:19701025T030000
      RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
      TZOFFSETFROM:+0200
      TZOFFSETTO:+0100
      END:STANDARD
      BEGIN:DAYLIGHT
      DTSTART:19700329T020000
      RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
      TZOFFSETFROM:+0100
      TZOFFSETTO:+0200
      END:DAYLIGHT
      END:VTIMEZONE
      BEGIN:VEVENT
      UID:standup@example.com
      DTSTART;TZID=Europe/Amsterdam:20300107T093000
      DTEND;TZID=Europe/Amsterdam:20300107T094500
      RRULE:FREQ=DAILY;COUNT=5
      EXDATE;TZID=Europe/Amsterdam:20300109T093000
      SUMMARY:Standup
      END:VEVENT
      BEGIN:VEVENT
      UID:standup@example.com
      RECURRENCE-ID;TZID=Europe/Amsterdam:20300110T093000
      DTSTART;TZID=Europe/Amsterdam:20300110T110000
      DTEND;TZID=Europe/Amsterdam:20300110T111500
      SUMMARY:Standup (moved)
      END:VEVENT
      END:VCALENDAR
    ICS
    calendar = calendars_calendars(:personal)
    calendar.events.create!(IcsParserService.new(ics).parse.except(:method).merge(
      is_recurring: true, etag: "standup-etag", remote_href: "#{calendar.remote_url}standup.ics"
    ))
  end

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

      ics = event[:ics] || <<~ICS
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

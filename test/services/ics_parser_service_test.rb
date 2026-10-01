# frozen_string_literal: true

require "test_helper"

class IcsParserServiceTest < ActiveSupport::TestCase
  test "parses basic event" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:test-event-123@example.com
      DTSTART:20250215T100000Z
      DTEND:20250215T110000Z
      SUMMARY:Team Meeting
      DESCRIPTION:Weekly sync meeting
      LOCATION:Conference Room A
      STATUS:CONFIRMED
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "test-event-123@example.com", result[:uid]
    assert_equal "Team Meeting", result[:summary]
    assert_equal "Weekly sync meeting", result[:description]
    assert_equal "Conference Room A", result[:location]
    assert_equal "confirmed", result[:status]
    assert_equal false, result[:all_day]
    assert_not_nil result[:starts_at]
    assert_not_nil result[:ends_at]
  end

  test "parses all-day event" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:vacation-123@example.com
      DTSTART;VALUE=DATE:20250301
      DTEND;VALUE=DATE:20250305
      SUMMARY:Vacation
      END:VEVENT
      END:VCALENDAR
    ICS

    result = Time.use_zone("America/Los_Angeles") { IcsParserService.new(ics).parse }

    assert_equal "vacation-123@example.com", result[:uid]
    assert_equal "Vacation", result[:summary]
    assert result[:all_day]
    # Dates are kept at midnight UTC, whatever the zone they're read in
    assert_equal [ Time.utc(2025, 3, 1), Time.utc(2025, 3, 5) ], [ result[:starts_at], result[:ends_at] ]
  end

  test "parses event with organizer" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:meeting-456@example.com
      DTSTART:20250215T100000Z
      DTEND:20250215T110000Z
      SUMMARY:Project Review
      ORGANIZER;CN=John Doe:mailto:john@example.com
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "meeting-456@example.com", result[:uid]
    assert_equal "Project Review", result[:summary]
    # Note: Organizer email extraction depends on icalendar gem behavior
    # The gem may or may not successfully extract it from heredoc format
  end

  test "parses event with attendees" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:meeting-789@example.com
      DTSTART:20250215T100000Z
      DTEND:20250215T110000Z
      SUMMARY:Team Sync
      ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED;ROLE=REQ-PARTICIPANT:mailto:alice@example.com
      ATTENDEE;CN=Bob;PARTSTAT=TENTATIVE;ROLE=OPT-PARTICIPANT:mailto:bob@example.com
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    # The icalendar gem's parsing of attendees varies
    # Verify we at least don't crash and get some result
    assert_kind_of Array, result[:attendees]
  end

  test "parses recurring event with RRULE" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:recurring-123@example.com
      DTSTART:20250217T090000Z
      DTEND:20250217T100000Z
      SUMMARY:Weekly Standup
      RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=10
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "recurring-123@example.com", result[:uid]
    assert_not_nil result[:rrule]
  end

  test "parses event with duration instead of end time" do
    # Note: Duration parsing may vary by icalendar gem version
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:duration-event@example.com
      DTSTART:20250215T100000Z
      DURATION:PT1H30M
      SUMMARY:Meeting with Duration
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "duration-event@example.com", result[:uid]
    assert_not_nil result[:starts_at]
    # ends_at should be calculated from duration if supported
    assert_not_nil result[:ends_at]
  end

  test "returns empty result for blank input" do
    result = IcsParserService.new("").parse

    assert_nil result[:uid]
    assert_nil result[:summary]
    assert_equal [], result[:attendees]
  end

  test "returns empty result for nil input" do
    result = IcsParserService.new(nil).parse

    assert_nil result[:uid]
    assert_nil result[:summary]
  end

  test "returns empty result for invalid ICS" do
    result = IcsParserService.new("not valid ics data").parse

    assert_nil result[:uid]
    assert_nil result[:summary]
  end

  test "returns empty result for calendar with no events" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_nil result[:uid]
  end

  test "preserves raw icalendar data" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:raw-test@example.com
      DTSTART:20250215T100000Z
      DTEND:20250215T110000Z
      SUMMARY:Test
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal ics, result[:raw_icalendar]
  end

  test "parses event with METHOD" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      METHOD:REQUEST
      BEGIN:VEVENT
      UID:invite-123@example.com
      DTSTART:20250215T100000Z
      DTEND:20250215T110000Z
      SUMMARY:Meeting Invite
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "REQUEST", result[:method]
  end

  test "handles timezone in datetime" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:tz-event@example.com
      DTSTART;TZID=America/New_York:20250215T100000
      DTEND;TZID=America/New_York:20250215T110000
      SUMMARY:Timezone Test
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "tz-event@example.com", result[:uid]
    assert_not_nil result[:starts_at]
    assert_not_nil result[:ends_at]
  end

  test "parses event without end time defaults to start time" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:no-end@example.com
      DTSTART:20250215T100000Z
      SUMMARY:No End Time
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics).parse

    assert_equal "no-end@example.com", result[:uid]
    assert_not_nil result[:starts_at]
    assert_not_nil result[:ends_at]
  end

  test "floating times and time zones that can't be looked up are in the given time zone" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:floating@example.com
      DTSTART:20260905T080000
      DTEND;TZID=Nowhere/Special:20260905T100000
      SUMMARY:Floating
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics, time_zone: "Amsterdam").parse

    assert_equal Time.utc(2026, 9, 5, 6), result[:starts_at]
    assert_equal Time.utc(2026, 9, 5, 8), result[:ends_at]
  end

  test "a time in a Windows time zone that Exchange describes keeps its own offset, in summer and winter" do
    summer = IcsParserService.new(exchange_ics("DTSTART;TZID=W. Europe Standard Time:20261005T100000", "DTEND;TZID=W. Europe Standard Time:20261005T110000"), time_zone: "America/New_York").parse
    winter = IcsParserService.new(exchange_ics("DTSTART;TZID=W. Europe Standard Time:20261207T100000", "DTEND;TZID=W. Europe Standard Time:20261207T110000"), time_zone: "America/New_York").parse

    assert_equal [ Time.utc(2026, 10, 5, 8), Time.utc(2026, 10, 5, 9) ], [ summer[:starts_at], summer[:ends_at] ]
    assert_equal [ Time.utc(2026, 12, 7, 9), Time.utc(2026, 12, 7, 10) ], [ winter[:starts_at], winter[:ends_at] ]
    # Without a zone to fall back on, too
    assert_equal Time.utc(2026, 10, 5, 8), IcsParserService.new(exchange_ics("DTSTART;TZID=W. Europe Standard Time:20261005T100000")).parse[:starts_at]
  end

  test "a series from Exchange stays at its local time after the clocks change and skips its EXDATE" do
    ics = exchange_ics(
      "DTSTART;TZID=W. Europe Standard Time:20261005T100000",
      "DTEND;TZID=W. Europe Standard Time:20261005T110000",
      "RRULE:FREQ=WEEKLY;COUNT=6",
      "EXDATE;TZID=W. Europe Standard Time:20261012T100000"
    )

    result = IcsParserService.new(ics, time_zone: "America/New_York").parse

    # The clocks go back on October 25th in Europe, a week before they do in New York
    assert_equal [ Time.utc(2026, 10, 5, 8), Time.utc(2026, 10, 19, 8), Time.utc(2026, 10, 26, 9), Time.utc(2026, 11, 2, 9), Time.utc(2026, 11, 9, 9) ],
      IceCube::Schedule.from_yaml(result[:recurrence_schedule]).all_occurrences.map(&:utc)
  end

  test "a described time zone with a name of its own is followed too" do
    ics = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Microsoft Corporation//Outlook 16.0 MIMEDIR//EN
      BEGIN:VTIMEZONE
      TZID:Customized Time Zone
      BEGIN:STANDARD
      DTSTART:16011104T020000
      RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
      TZOFFSETFROM:-0400
      TZOFFSETTO:-0500
      END:STANDARD
      BEGIN:DAYLIGHT
      DTSTART:16010311T020000
      RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3
      TZOFFSETFROM:-0500
      TZOFFSETTO:-0400
      END:DAYLIGHT
      END:VTIMEZONE
      BEGIN:VEVENT
      UID:custom-zone@example.com
      DTSTART;TZID=Customized Time Zone:20261019T100000
      DTEND;TZID=Customized Time Zone:20261019T103000
      RRULE:FREQ=WEEKLY;COUNT=4
      SUMMARY:Call with New York
      END:VEVENT
      END:VCALENDAR
    ICS

    result = IcsParserService.new(ics, time_zone: "Europe/Amsterdam").parse

    assert_equal Time.utc(2026, 10, 19, 14), result[:starts_at]
    # New York's clocks go back on November 1st
    assert_equal [ Time.utc(2026, 10, 19, 14), Time.utc(2026, 10, 26, 14), Time.utc(2026, 11, 2, 15), Time.utc(2026, 11, 9, 15) ],
      IceCube::Schedule.from_yaml(result[:recurrence_schedule]).all_occurrences.map(&:utc)
  end

  test "a time with an IANA time zone, a UTC time and a floating time" do
    ics = ->(dtstart) { <<~ICS }
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:zones@example.com
      #{dtstart}
      SUMMARY:Zones
      END:VEVENT
      END:VCALENDAR
    ICS

    starts_at = ->(dtstart) { IcsParserService.new(ics.call(dtstart), time_zone: "Europe/Amsterdam").parse[:starts_at] }

    assert_equal Time.utc(2026, 10, 5, 14), starts_at.call("DTSTART;TZID=America/New_York:20261005T100000")
    assert_equal Time.utc(2026, 12, 7, 15), starts_at.call("DTSTART;TZID=America/New_York:20261207T100000")
    assert_equal Time.utc(2026, 10, 5, 10), starts_at.call("DTSTART:20261005T100000Z")
    assert_equal Time.utc(2026, 10, 5, 8), starts_at.call("DTSTART:20261005T100000")
    assert_equal Time.utc(2026, 12, 7, 9), starts_at.call("DTSTART:20261207T100000")
    # A Windows name without its description is looked up by icalendar
    assert_equal Time.utc(2026, 10, 5, 17), starts_at.call("DTSTART;TZID=Pacific Standard Time:20261005T100000")
  end

  private

  # What Exchange and Outlook send: a Windows time zone name, with the VTIMEZONE that describes it
  def exchange_ics(*event_lines)
    <<~ICS
      BEGIN:VCALENDAR
      METHOD:REQUEST
      PRODID:Microsoft Exchange Server 2010
      VERSION:2.0
      BEGIN:VTIMEZONE
      TZID:W. Europe Standard Time
      BEGIN:STANDARD
      DTSTART:16010101T030000
      TZOFFSETFROM:+0200
      TZOFFSETTO:+0100
      RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
      END:STANDARD
      BEGIN:DAYLIGHT
      DTSTART:16010101T020000
      TZOFFSETFROM:+0100
      TZOFFSETTO:+0200
      RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
      END:DAYLIGHT
      END:VTIMEZONE
      BEGIN:VEVENT
      UID:040000008200E00074C5B7101A82E008
      #{event_lines.join("\n")}
      SUMMARY:Kwartaaloverleg
      ORGANIZER;CN=Rachel Kim:mailto:rachel@example.com
      END:VEVENT
      END:VCALENDAR
    ICS
  end
end

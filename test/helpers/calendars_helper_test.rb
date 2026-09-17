# frozen_string_literal: true

require "test_helper"

class CalendarsHelperTest < ActionView::TestCase
  include FormattingHelper

  test "day_columns puts overlapping events side by side and the others full width" do
    day = Date.new(2030, 1, 8)
    review = event("Design review", "12:00", "13:30")
    call = event("Call", "12:30", "13:00")
    lunch = event("Lunch", "13:00", "13:45")
    gym = event("Gym", "16:00", "17:00")
    quick = event("Quick check", "16:00", "16:00")

    columns = day_columns([ gym, lunch, call, review, quick ], day).to_h { |event, column, count| [ event.summary, [ column, count ] ] }

    assert_equal({
      "Design review" => [ 0, 2 ], "Call" => [ 1, 2 ], "Lunch" => [ 1, 2 ],
      "Gym" => [ 0, 2 ], "Quick check" => [ 1, 2 ]
    }, columns)
  end

  test "day_columns only counts the part of an event on that day" do
    night = event("Night", "2030-01-07 22:00", "02:00")
    early = event("Early", "03:00", "04:00")

    assert_equal [ [ night, 0, 1 ], [ early, 0, 1 ] ], day_columns([ night, early ], Date.new(2030, 1, 8))
  end

  test "format_event_time uses the app's time and date formats" do
    travel_to Time.zone.local(2030, 1, 1) do
      assert_equal "Jan 8, 12:00 PM – 1:30 PM", format_event_time(event("Review", "12:00", "13:30"))
      assert_equal "Jan 7, 10:00 PM – Jan 8, 2:00 AM", format_event_time(event("Night", "2030-01-07 22:00", "02:00"))
    end
  end

  test "format_event_time shows all-day events by their dates, whatever the zone" do
    trip = Calendars::Event.new(all_day: true, starts_at: Time.utc(2030, 1, 8), ends_at: Time.utc(2030, 1, 11))
    holiday = Calendars::Event.new(all_day: true, starts_at: Time.utc(2030, 1, 8), ends_at: Time.utc(2030, 1, 9))

    travel_to Time.utc(2030, 1, 2) do
      Time.use_zone("America/Los_Angeles") do
        assert_equal "Jan 8 – Jan 10", format_event_time(trip)
        assert_equal "Jan 8", format_event_time(holiday)
      end
    end
  end

  private

  def event(summary, starts, ends)
    starts = starts.include?("-") ? Time.zone.parse(starts) : Time.zone.parse("2030-01-08 #{starts}")
    Calendars::Event.new(summary: summary, starts_at: starts, ends_at: Time.zone.parse("2030-01-08 #{ends}"))
  end
end

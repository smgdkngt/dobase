# frozen_string_literal: true

require "test_helper"

module Calendars
  class ReminderTest < ActiveSupport::TestCase
    setup { @start = Time.use_zone("Amsterdam") { Time.zone.local(2026, 12, 1, 10) } }

    def parse(value, starts_at: @start, all_day: false)
      Time.use_zone("Amsterdam") { Reminder.parse(value, starts_at: starts_at, all_day: all_day) }
    end

    def label(minutes, starts_at: @start, all_day: false)
      Time.use_zone("Amsterdam") { Reminder.label(minutes, starts_at: starts_at, all_day: all_day) }
    end

    test "reads minutes, spans and a time on a day before the start" do
      assert_equal 75, parse(75)
      assert_equal 75, parse("75")
      assert_equal 45, parse("45m")
      assert_equal 120, parse("2h")
      assert_equal 1440, parse("1d")
      assert_equal 10_080, parse("1w")
      # Tuesday 10:00: the day before at 17:00 is 17 hours before, 08:45 that day 75 minutes
      assert_equal 1020, parse("1d@17:00")
      assert_equal 75, parse("@08:45")
      assert_equal 75, parse(" 0d@08:45 ")
    end

    test "an all-day appointment counts back from midnight, and may alert on the day itself" do
      day = Time.utc(2026, 12, 1)
      assert_equal 900, parse("1d@09:00", starts_at: day, all_day: true)
      assert_equal(-540, parse("@09:00", starts_at: day, all_day: true))
      assert_equal "The day before at 9:00 AM", label(900, starts_at: day, all_day: true)
      assert_equal "On the day at 9:00 AM", label(-540, starts_at: day, all_day: true)
    end

    test "refuses what isn't an alert, one after the start and one too long before" do
      [ "soon", "1y", "25:00", "@10:30", "-5", "5w" ].each do |value|
        assert_raises(Reminder::Invalid, value) { parse(value) }
      end
    end

    test "says an alert in words" do
      assert_equal "At the start", label(0)
      assert_equal "15 minutes before", label(15)
      assert_equal "1 hour 15 minutes before", label(75)
      assert_equal "2 hours before", label(120)
      assert_equal "1 day before", label(1440)
      assert_equal "1 week before", label(10_080)
      assert_equal "The day before at 5:00 PM", label(1020)
      assert_equal "2 days before at 9:00 AM", label(2940)
    end

    test "writes a VALARM trigger before the start, and after it for a time on the day" do
      assert_equal "PT0S", Reminder.trigger(0)
      assert_equal "-PT1H15M", Reminder.trigger(75)
      assert_equal "-PT17H", Reminder.trigger(1020)
      assert_equal "-P1D", Reminder.trigger(1440)
      assert_equal "PT9H", Reminder.trigger(-540)
    end
  end
end

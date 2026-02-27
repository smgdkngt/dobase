# frozen_string_literal: true

require "test_helper"

module Calendars
  class EventTest < ActiveSupport::TestCase
    test "belongs to a calendar" do
      event = calendars_events(:meeting)
      assert_equal calendars_calendars(:personal), event.calendar
    end

    test "has one account through calendar" do
      event = calendars_events(:meeting)
      assert_equal calendars_accounts(:icloud_account), event.account
    end

    test "validates uid presence" do
      event = build_event(uid: nil)
      assert_not event.valid?
      assert_includes event.errors[:uid], "can't be blank"
    end

    test "validates summary presence" do
      event = build_event(summary: nil)
      assert_not event.valid?
      assert_includes event.errors[:summary], "can't be blank"
    end

    test "validates starts_at presence" do
      event = build_event(starts_at: nil)
      assert_not event.valid?
      assert_includes event.errors[:starts_at], "can't be blank"
    end

    test "validates ends_at presence" do
      event = build_event(ends_at: nil)
      assert_not event.valid?
      assert_includes event.errors[:ends_at], "can't be blank"
    end

    test "validates ends_at is after starts_at" do
      event = build_event(
        starts_at: 1.hour.from_now,
        ends_at: 1.hour.ago
      )
      assert_not event.valid?
      assert_includes event.errors[:ends_at], "must be after starts_at"
    end

    test "allows ends_at equal to starts_at" do
      time = 1.hour.from_now
      event = build_event(starts_at: time, ends_at: time)
      assert event.valid?
    end

    test "validates status inclusion" do
      event = calendars_events(:meeting)

      %w[tentative confirmed cancelled].each do |status|
        event.status = status
        assert event.valid?, "Expected #{status} to be valid"
      end

      event.status = nil
      assert event.valid?, "Expected nil status to be valid"

      event.status = "invalid"
      assert_not event.valid?
    end

    test "start_time alias returns starts_at" do
      event = calendars_events(:meeting)
      assert_equal event.starts_at, event.start_time
    end

    test "end_time alias returns ends_at" do
      event = calendars_events(:meeting)
      assert_equal event.ends_at, event.end_time
    end

    test "in_range scope returns events overlapping date range" do
      calendar = calendars_calendars(:personal)

      # Create events with known times
      past_event = Calendars::Event.create!(
        calendar: calendar,
        uid: "past-event",
        summary: "Past Event",
        starts_at: 2.days.ago,
        ends_at: 1.day.ago
      )

      current_event = Calendars::Event.create!(
        calendar: calendar,
        uid: "current-event",
        summary: "Current Event",
        starts_at: 1.hour.ago,
        ends_at: 1.hour.from_now
      )

      future_event = Calendars::Event.create!(
        calendar: calendar,
        uid: "future-event",
        summary: "Future Event",
        starts_at: 2.days.from_now,
        ends_at: 3.days.from_now
      )

      # Query for events today
      today_start = Time.current.beginning_of_day
      today_end = Time.current.end_of_day

      results = Calendars::Event.in_range(today_start, today_end)

      assert_includes results, current_event
      assert_not_includes results, past_event
      assert_not_includes results, future_event
    end

    test "recurring scope returns recurring events" do
      calendar = calendars_calendars(:personal)

      recurring = Calendars::Event.create!(
        calendar: calendar,
        uid: "recurring-event",
        summary: "Weekly Meeting",
        starts_at: 1.hour.from_now,
        ends_at: 2.hours.from_now,
        is_recurring: true,
        rrule: "FREQ=WEEKLY;BYDAY=MO"
      )

      non_recurring = calendars_events(:meeting)

      results = Calendars::Event.recurring

      assert_includes results, recurring
      assert_not_includes results, non_recurring
    end

    test "non_recurring scope returns non-recurring events" do
      calendar = calendars_calendars(:personal)

      recurring = Calendars::Event.create!(
        calendar: calendar,
        uid: "recurring-event-2",
        summary: "Weekly Meeting",
        starts_at: 1.hour.from_now,
        ends_at: 2.hours.from_now,
        is_recurring: true
      )

      non_recurring = calendars_events(:meeting)

      results = Calendars::Event.non_recurring

      assert_includes results, non_recurring
      assert_not_includes results, recurring
    end

    test "by_start scope orders by starts_at ascending" do
      calendar = calendars_calendars(:personal)

      # Clear existing events
      calendar.events.destroy_all

      later = Calendars::Event.create!(
        calendar: calendar,
        uid: "later-event",
        summary: "Later",
        starts_at: 2.hours.from_now,
        ends_at: 3.hours.from_now
      )

      earlier = Calendars::Event.create!(
        calendar: calendar,
        uid: "earlier-event",
        summary: "Earlier",
        starts_at: 1.hour.from_now,
        ends_at: 2.hours.from_now
      )

      results = calendar.events.by_start
      assert_equal earlier, results.first
      assert_equal later, results.second
    end

    test "attendees returns empty array for blank json" do
      event = calendars_events(:meeting)
      event.attendees_json = nil
      assert_equal [], event.attendees
    end

    test "attendees returns parsed json" do
      event = calendars_events(:meeting)
      attendees_data = [
        { "email" => "alice@example.com", "name" => "Alice", "status" => "accepted" },
        { "email" => "bob@example.com", "name" => "Bob", "status" => "tentative" }
      ]
      event.attendees = attendees_data

      assert_equal attendees_data, event.attendees
    end

    test "attendees handles invalid json gracefully" do
      event = calendars_events(:meeting)
      event.attendees_json = "not valid json"
      assert_equal [], event.attendees
    end

    test "duration_minutes calculates correctly" do
      event = calendars_events(:meeting)
      event.starts_at = Time.current
      event.ends_at = 90.minutes.from_now

      assert_equal 90, event.duration_minutes
    end

    test "duration_hours calculates correctly" do
      event = calendars_events(:meeting)
      event.starts_at = Time.current
      event.ends_at = 90.minutes.from_now

      assert_equal 1.5, event.duration_hours
    end

    test "multi_day? returns true for events spanning multiple days" do
      event = calendars_events(:multi_day_event)
      assert event.multi_day?
    end

    test "multi_day? returns false for same-day events" do
      event = calendars_events(:meeting)
      assert_not event.multi_day?
    end

    test "all_day event" do
      event = calendars_events(:all_day_event)
      assert event.all_day?
    end

    # -- Recurrence: building from form --

    test "builds daily recurrence from form" do
      event = build_event(recurrence_frequency: "daily", recurrence_interval: 1, recurrence_end_type: "never")
      assert event.valid?
      assert event.is_recurring?
      assert_equal "FREQ=DAILY", event.rrule
      assert event.recurrence_schedule.present?
    end

    test "builds daily recurrence with interval" do
      event = build_event(recurrence_frequency: "daily", recurrence_interval: 3, recurrence_end_type: "never")
      assert event.valid?
      assert_equal "FREQ=DAILY;INTERVAL=3", event.rrule
    end

    test "builds weekly recurrence with days" do
      event = build_event(
        recurrence_frequency: "weekly",
        recurrence_interval: 2,
        recurrence_days_of_week: [ "MO", "WE", "FR" ],
        recurrence_end_type: "never"
      )
      assert event.valid?
      assert_equal "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR", event.rrule
    end

    test "builds monthly recurrence by day of month" do
      event = build_event(
        starts_at: Time.zone.local(2026, 2, 15, 10, 0),
        ends_at: Time.zone.local(2026, 2, 15, 11, 0),
        recurrence_frequency: "monthly",
        recurrence_interval: 1,
        recurrence_monthly_by: "day_of_month",
        recurrence_end_type: "count",
        recurrence_count: 12
      )
      assert event.valid?
      assert_match(/FREQ=MONTHLY/, event.rrule)
      assert_match(/BYMONTHDAY=15/, event.rrule)
      assert_match(/COUNT=12/, event.rrule)
    end

    test "builds monthly recurrence by day of week" do
      # Feb 16 2026 is a Monday, 3rd week
      event = build_event(
        starts_at: Time.zone.local(2026, 2, 16, 10, 0),
        ends_at: Time.zone.local(2026, 2, 16, 11, 0),
        recurrence_frequency: "monthly",
        recurrence_interval: 1,
        recurrence_monthly_by: "day_of_week",
        recurrence_end_type: "never"
      )
      assert event.valid?
      assert_match(/BYDAY=3MO/, event.rrule)
    end

    test "builds yearly recurrence" do
      event = build_event(recurrence_frequency: "yearly", recurrence_interval: 1, recurrence_end_type: "never")
      assert event.valid?
      assert_equal "FREQ=YEARLY", event.rrule
    end

    test "builds recurrence with until end condition" do
      event = build_event(
        recurrence_frequency: "daily",
        recurrence_interval: 1,
        recurrence_end_type: "until",
        recurrence_until: "2026-06-30"
      )
      assert event.valid?
      assert_match(/UNTIL=20260630/, event.rrule)
    end

    test "setting frequency to none clears recurrence" do
      event = build_event(
        is_recurring: true,
        rrule: "FREQ=DAILY",
        recurrence_schedule: "---yaml---",
        recurrence_frequency: "none"
      )
      event.valid?
      assert_not event.is_recurring?
      assert_nil event.rrule
      assert_nil event.recurrence_schedule
    end

    # -- Recurrence: loading for form --

    test "load_recurrence_for_form parses weekly rrule" do
      event = build_event(rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE")
      event.load_recurrence_for_form
      assert_equal "weekly", event.recurrence_frequency
      assert_equal "2", event.recurrence_interval.to_s
      assert_equal [ "MO", "WE" ], event.recurrence_days_of_week
      assert_equal "never", event.recurrence_end_type
    end

    test "load_recurrence_for_form parses count end condition" do
      event = build_event(rrule: "FREQ=DAILY;COUNT=5")
      event.load_recurrence_for_form
      assert_equal "daily", event.recurrence_frequency
      assert_equal "count", event.recurrence_end_type
      assert_equal "5", event.recurrence_count
    end

    test "load_recurrence_for_form parses until end condition" do
      event = build_event(rrule: "FREQ=MONTHLY;UNTIL=20260630T235959Z")
      event.load_recurrence_for_form
      assert_equal "monthly", event.recurrence_frequency
      assert_equal "until", event.recurrence_end_type
      assert_equal "2026-06-30", event.recurrence_until
    end

    test "load_recurrence_for_form sets none for blank rrule" do
      event = build_event(rrule: nil)
      event.load_recurrence_for_form
      assert_equal "none", event.recurrence_frequency
    end

    # -- Recurrence: description --

    test "recurrence_description for daily event" do
      event = build_event(is_recurring: true, rrule: "FREQ=DAILY")
      assert_equal "Daily", event.recurrence_description
    end

    test "recurrence_description for weekly event with days" do
      event = build_event(is_recurring: true, rrule: "FREQ=WEEKLY;BYDAY=MO,WE,FR")
      assert_equal "Weekly on Monday, Wednesday, Friday", event.recurrence_description
    end

    test "recurrence_description for monthly event with count" do
      event = build_event(is_recurring: true, rrule: "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12")
      assert_equal "Monthly on day 15, 12 times", event.recurrence_description
    end

    test "recurrence_description for yearly event" do
      event = build_event(is_recurring: true, rrule: "FREQ=YEARLY;INTERVAL=2")
      assert_equal "Every 2 years", event.recurrence_description
    end

    test "recurrence_description returns nil for non-recurring" do
      event = build_event(is_recurring: false)
      assert_nil event.recurrence_description
    end

    # -- Recurrence: editability --

    test "recurrence_editable? returns true for simple rrules" do
      event = build_event(rrule: "FREQ=WEEKLY;BYDAY=MO")
      assert event.recurrence_editable?
    end

    test "recurrence_editable? returns true for blank rrule" do
      event = build_event(rrule: nil)
      assert event.recurrence_editable?
    end

    test "recurrence_editable? returns false for complex rrules" do
      event = build_event(rrule: "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=2")
      assert_not event.recurrence_editable?
    end

    private

    def build_event(overrides = {})
      defaults = {
        calendar: calendars_calendars(:personal),
        uid: "test-event-#{SecureRandom.hex(4)}",
        summary: "Test Event",
        starts_at: 1.hour.from_now,
        ends_at: 2.hours.from_now
      }

      Calendars::Event.new(defaults.merge(overrides))
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260916130000_pin_all_day_events_to_dates")

class PinAllDayEventsToDatesTest < ActiveSupport::TestCase
  setup do
    @calendar = calendars_calendars(:personal)
    users(:one).update!(timezone: "Amsterdam")
    users(:two).update!(timezone: "Eastern Time (US & Canada)")
  end

  test "moves all-day events made in Dobase to their dates, read in the time zone of their maker" do
    amsterdam = legacy_event(users(:one), "2030-01-10 00:00 +01:00", "2030-01-11 23:59:59 +01:00")
    new_york = legacy_event(users(:two), "2030-01-10 00:00 -05:00", "2030-01-10 23:59:59 -05:00")
    synced = legacy_event(nil, "2030-01-10 00:00 UTC", "2030-01-12 00:00 UTC")
    empty = legacy_event(nil, "2030-01-10 00:00 UTC", "2030-01-10 00:00 UTC")

    assert_no_changes -> { amsterdam.reload.updated_at } do
      migrate
    end

    assert_equal [ Time.utc(2030, 1, 10), Time.utc(2030, 1, 12) ], [ amsterdam.reload.starts_at, amsterdam.ends_at ]
    assert_equal [ Time.utc(2030, 1, 10), Time.utc(2030, 1, 11) ], [ new_york.reload.starts_at, new_york.ends_at ]
    assert_equal [ Time.utc(2030, 1, 10), Time.utc(2030, 1, 12) ], [ synced.reload.starts_at, synced.ends_at ]
    assert_equal [ Time.utc(2030, 1, 10), Time.utc(2030, 1, 11) ], [ empty.reload.starts_at, empty.ends_at ]
  end

  test "moves the schedule of a repeating all-day event to its dates" do
    event = legacy_event(users(:two), "2030-01-10 00:00 -05:00", "2030-01-10 23:59:59 -05:00")
    schedule = Time.use_zone("Eastern Time (US & Canada)") do
      IceCube::Schedule.new(Time.zone.parse("2030-01-10 00:00")) do |s|
        s.add_recurrence_rule IceCube::Rule.monthly.day_of_month(10).until(Date.new(2030, 7, 10).end_of_day)
      end
    end
    event.update_columns(is_recurring: true, rrule: "FREQ=MONTHLY;BYMONTHDAY=10;UNTIL=20300710T235959Z", recurrence_schedule: schedule.to_yaml)

    migrate

    occurrences = IceCube::Schedule.from_yaml(event.reload.recurrence_schedule).all_occurrences
    assert_equal (1..7).map { |month| Time.utc(2030, month, 10) }, occurrences
  end

  private

  def legacy_event(maker, starts_at, ends_at)
    @calendar.events.create!(uid: SecureRandom.uuid, summary: "All day", starts_at: 1.hour.from_now, ends_at: 2.hours.from_now, created_by: maker).tap do |event|
      event.update_columns(all_day: true, starts_at: Time.zone.parse(starts_at), ends_at: Time.zone.parse(ends_at))
    end
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { PinAllDayEventsToDates.new.up }
  end
end

# frozen_string_literal: true

class PinAllDayEventsToDates < ActiveRecord::Migration[8.1]
  class Event < ActiveRecord::Base
    self.table_name = "calendar_events"
  end

  class User < ActiveRecord::Base
    self.table_name = "users"
  end

  # All-day events now run from midnight UTC on their first day to midnight UTC after their last,
  # as synced ones already did. Those made in Dobase ran from midnight to 23:59 in the time zone
  # of whoever made them, so their dates are read there.
  def up
    Event.where(all_day: true).find_each do |event|
      next if midnight_utc?(event.starts_at) && midnight_utc?(event.ends_at) && event.ends_at > event.starts_at

      zone = ActiveSupport::TimeZone[User.find_by(id: event.created_by_id)&.timezone.to_s] || ActiveSupport::TimeZone["UTC"]
      starts, ends = [ event.starts_at, event.ends_at ].map { |time| midnight_utc?(time) ? time.utc : time.in_time_zone(zone) }
      first_day = starts.to_date
      last_day = [ ends == ends.midnight && ends > starts ? ends.to_date - 1 : ends.to_date, first_day ].max
      new_start = first_day.to_time(:utc)

      # Without touching updated_at, which would mark the calendar as changed for everyone
      event.update_columns(
        starts_at: new_start,
        ends_at: (last_day + 1).to_time(:utc),
        recurrence_schedule: event.recurrence_schedule.presence && schedule_from(event.recurrence_schedule, new_start)
      )
    end
  end

  def down
    # The events keep their days
  end

  private

  def midnight_utc?(time)
    time.utc == time.utc.midnight
  end

  # The schedule of an all-day event runs in UTC too
  def schedule_from(yaml, start)
    schedule = IceCube::Schedule.from_yaml(yaml)
    schedule.start_time = start
    schedule.recurrence_rules.each do |rule|
      rule.until(rule.until_time.to_date.to_time(:utc).end_of_day) if rule.until_time
    end
    schedule.to_yaml
  rescue StandardError
    yaml # The calendar skips a schedule it can't read as well
  end
end

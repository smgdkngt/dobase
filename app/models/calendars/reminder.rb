# frozen_string_literal: true

module Calendars
  # An alert before an appointment, as a calendar app gives it: a number of minutes before the
  # start (a VALARM's TRIGGER). Dobase keeps them and writes them to the calendar's server; the
  # calendar app on someone's phone or computer gives the alert, not Dobase.
  #
  # An all-day appointment starts at midnight wherever it is looked at, so its alerts count back
  # from that midnight, and one after it (a negative number) is a time on the day itself:
  # -540 is 09:00 on the day, 900 is 09:00 the day before.
  module Reminder
    LIMIT = 10
    LONGEST = 4.weeks.in_minutes.to_i
    UNITS = { "m" => 1, "min" => 1, "h" => 60, "d" => 1440, "w" => 10_080 }.freeze

    # What the form offers, as the API takes it; "1d@17:00" counts from the appointment's start
    CHOICES = [
      [ "At the start", "0" ], [ "5 minutes before", "5m" ], [ "10 minutes before", "10m" ],
      [ "15 minutes before", "15m" ], [ "30 minutes before", "30m" ], [ "1 hour before", "1h" ],
      [ "2 hours before", "2h" ], [ "1 day before", "1d" ], [ "2 days before", "2d" ], [ "1 week before", "1w" ],
      [ "On the day at 9:00 AM", "0d@09:00" ], [ "The day before at 9:00 AM", "1d@09:00" ],
      [ "The day before at 5:00 PM", "1d@17:00" ]
    ].freeze

    class Invalid < ArgumentError; end

    module_function

    # Minutes before the start, from what someone wrote: 75, "75", "45m", "2h", "1d", "1w", or a
    # time on a day before the start, "1d@17:00" (the day before at five) or "@08:45" (that day).
    # Those times are in the time zone of whoever sets them (Time.zone).
    def parse(value, starts_at:, all_day:)
      text = value.to_s.strip.downcase.delete(" ")
      minutes = case text
      when /\A-?\d+\z/ then text.to_i
      when /\A(\d+)(m|min|h|d|w)\z/ then $1.to_i * UNITS.fetch($2)
      when /\A(?:(\d+)d)?@(\d{1,2}):(\d{2})\z/ then at_time(($1 || 0).to_i, $2.to_i, $3.to_i, starts_at, all_day)
      else raise Invalid, "#{value.to_s.inspect} isn't an alert: write 45m, 2h, 1d or 1d@17:00"
      end

      earliest = all_day ? -1439 : 0
      raise Invalid, "#{value} is after the start" if minutes < earliest
      raise Invalid, "#{value} is more than 4 weeks before" if minutes > LONGEST

      minutes
    end

    def at_time(days, hour, minute, starts_at, all_day)
      raise Invalid, "#{hour}:#{minute} isn't a time" if hour > 23 || minute > 59
      raise Invalid, "the alert needs the appointment's start first" unless starts_at

      start = all_day ? Time.zone.local(starts_at.utc.year, starts_at.utc.month, starts_at.utc.day) : starts_at.in_time_zone
      day = start.to_date - days
      ((start - Time.zone.local(day.year, day.month, day.day, hour, minute)) / 60).round
    end

    # "15 minutes before", "2 hours before", "1 day before", or "The day before at 5:00 PM",
    # in the page's language (English for the API)
    def label(minutes, starts_at:, all_day:)
      return clock_label(minutes, midnight_of(starts_at), 0) if all_day
      return t("At the start") if minutes.zero?
      return t("%{time} before", time: count(minutes / 10_080, "week")) if (minutes % 10_080).zero?
      return t("%{time} before", time: count(minutes / 1440, "day")) if (minutes % 1440).zero?
      return t("%{time} before", time: duration(minutes)) if minutes < 720 || starts_at.nil?

      start = starts_at.in_time_zone
      clock_label(minutes, start.beginning_of_day, start.seconds_since_midnight)
    end

    def clock_label(minutes, midnight, start_seconds)
      at = midnight + start_seconds - minutes.minutes
      days = (midnight.to_date - at.to_date).to_i
      clock = Translation.localize(at, :clock) # as FormattingHelper#format_time
      case days
      when 0 then t("On the day at %{time}", time: clock)
      when 1 then t("The day before at %{time}", time: clock)
      else Translation.translate_plural("%{count} day before at %{time}", "%{count} days before at %{time}", days, time: clock)
      end
    end

    def midnight_of(starts_at)
      date = (starts_at || Time.current).utc.to_date
      Time.utc(date.year, date.month, date.day)
    end

    def duration(minutes)
      hours, rest = minutes.divmod(60)
      return count(rest, "minute") if hours.zero?
      return count(hours, "hour") if rest.zero?

      Translation.translate("%{hours} %{minutes}", hours: count(hours, "hour"), minutes: count(rest, "minute"))
    end

    def count(number, unit)
      case unit
      when "week" then Translation.translate_plural("%{count} week", "%{count} weeks", number)
      when "day" then Translation.translate_plural("%{count} day", "%{count} days", number)
      when "hour" then Translation.translate_plural("%{count} hour", "%{count} hours", number)
      else Translation.translate_plural("%{count} minute", "%{count} minutes", number)
      end
    end

    def t(text, **values) = Translation.translate(text, **values)

    # The minutes before the start a VALARM goes off, or nil for one that is no alert to show:
    # ACTION:NONE (what Apple leaves of a default alert taken away), an e-mail, or a trigger
    # that can't be read.
    def minutes_of_alarm(alarm, starts_at:, ends_at:)
      return unless alarm.action.to_s.upcase.in?(%w[DISPLAY AUDIO])

      trigger = alarm.trigger
      case trigger
      when Icalendar::Values::Duration
        seconds = ((trigger.weeks * 7 + trigger.days) * 86_400) + (trigger.hours * 3600) + (trigger.minutes * 60) + trigger.seconds
        seconds = -seconds if trigger.past
        from_end = trigger.ical_params["related"].to_a.first.to_s.upcase == "END"
        seconds += (ends_at - starts_at).to_i if from_end && starts_at && ends_at
        (-seconds / 60.0).round
      when Icalendar::Values::DateTime
        ((starts_at - trigger.to_time) / 60).round if starts_at
      end
    rescue StandardError
      nil
    end

    # The VALARM for an alert Dobase made
    def alarm(minutes, summary)
      Icalendar::Alarm.new.tap do |alarm|
        alarm.action = "DISPLAY"
        alarm.description = summary.presence || "Reminder"
        alarm.trigger = trigger(minutes)
      end
    end

    def trigger(minutes)
      return "PT0S" if minutes.zero?

      sign = minutes.negative? ? "" : "-"
      days, rest = minutes.abs.divmod(1440)
      hours, mins = rest.divmod(60)
      time = [ ("#{hours}H" if hours.positive?), ("#{mins}M" if mins.positive?) ].join
      "#{sign}P#{"#{days}D" if days.positive?}#{"T#{time}" if time.present?}"
    end
  end
end

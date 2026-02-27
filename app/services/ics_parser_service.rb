# frozen_string_literal: true

require "icalendar"
require "ice_cube"

class IcsParserService
  def initialize(ics_data)
    @ics_data = ics_data
  end

  def parse
    return empty_result if @ics_data.blank?

    calendars = Icalendar::Calendar.parse(@ics_data)
    return empty_result if calendars.empty?

    calendar = calendars.first
    event = calendar.events.first
    return empty_result unless event

    {
      uid: event.uid.to_s,
      method: calendar.ip_method&.to_s,
      summary: event.summary.to_s,
      description: event.description&.to_s,
      location: event.location&.to_s,
      starts_at: parse_datetime(event.dtstart),
      ends_at: parse_end_datetime(event),
      all_day: all_day?(event),
      organizer_email: extract_email(event.organizer),
      organizer_name: extract_name(event.organizer),
      attendees: parse_attendees(event.attendee),
      rrule: extract_rrule(event),
      recurrence_schedule: build_schedule(event),
      status: event.status&.to_s&.downcase,
      raw_icalendar: @ics_data
    }
  rescue Icalendar::Parser::ParseError, StandardError => e
    Rails.logger.warn("Failed to parse ICS data: #{e.message}")
    empty_result
  end

  private

  def empty_result
    {
      uid: nil,
      method: nil,
      summary: nil,
      description: nil,
      location: nil,
      starts_at: nil,
      ends_at: nil,
      all_day: false,
      organizer_email: nil,
      organizer_name: nil,
      attendees: [],
      rrule: nil,
      recurrence_schedule: nil,
      status: nil,
      raw_icalendar: @ics_data
    }
  end

  def parse_datetime(dt)
    return nil unless dt

    if dt.is_a?(Icalendar::Values::Date)
      dt.to_date.beginning_of_day
    elsif dt.respond_to?(:to_time)
      dt.to_time.in_time_zone
    else
      Time.zone.parse(dt.to_s)
    end
  rescue ArgumentError
    nil
  end

  def parse_end_datetime(event)
    if event.dtend.present?
      parse_datetime(event.dtend)
    elsif event.duration.present?
      starts = parse_datetime(event.dtstart)
      starts + parse_duration(event.duration) if starts
    elsif all_day?(event)
      # All-day event with no end date defaults to 1 day
      starts = parse_datetime(event.dtstart)
      starts + 1.day if starts
    else
      parse_datetime(event.dtstart)
    end
  end

  def parse_duration(duration)
    return 0 unless duration

    # ISO 8601 duration (e.g., PT1H30M, P1D)
    if duration.respond_to?(:to_s)
      duration_str = duration.to_s
      seconds = 0

      if match = duration_str.match(/P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
        seconds += (match[1].to_i * 86400) # days
        seconds += (match[2].to_i * 3600)  # hours
        seconds += (match[3].to_i * 60)    # minutes
        seconds += match[4].to_i           # seconds
      end

      seconds.seconds
    else
      0
    end
  end

  def all_day?(event)
    return false unless event.dtstart
    event.dtstart.is_a?(Icalendar::Values::Date)
  end

  def extract_email(cal_address)
    return nil unless cal_address

    if cal_address.respond_to?(:to_s)
      addr = cal_address.to_s
      addr.gsub(/^mailto:/i, "").strip
    else
      nil
    end
  end

  def extract_name(cal_address)
    return nil unless cal_address

    if cal_address.respond_to?(:ical_params) && cal_address.ical_params
      params = cal_address.ical_params
      cn = (params["cn"] || []).first
      cn&.to_s
    else
      nil
    end
  end

  def parse_attendees(attendees)
    return [] unless attendees

    Array(attendees).filter_map do |attendee|
      email = extract_email(attendee)
      next unless email.present?

      params = attendee.respond_to?(:ical_params) ? (attendee.ical_params || {}) : {}

      {
        "email" => email,
        "name" => (params["cn"] || []).first&.to_s,
        "status" => (params["partstat"] || []).first&.to_s&.downcase,
        "role" => (params["role"] || []).first&.to_s&.downcase,
        "rsvp" => (params["rsvp"] || []).first&.to_s&.downcase == "true"
      }
    end
  end

  def extract_rrule(event)
    return nil unless event.rrule.present?

    rrule = event.rrule.first
    return nil unless rrule

    if rrule.respond_to?(:value_ical)
      rrule.value_ical
    elsif rrule.respond_to?(:to_s)
      rrule.to_s
    else
      nil
    end
  end

  def build_schedule(event)
    return nil unless event.rrule.present?

    start_time = parse_datetime(event.dtstart)
    return nil unless start_time

    schedule = IceCube::Schedule.new(start_time)

    event.rrule.each do |rrule|
      rule = parse_rrule_to_ice_cube(rrule, start_time)
      schedule.add_recurrence_rule(rule) if rule
    end

    # Add exception dates (EXDATE)
    if event.exdate.present?
      event.exdate.each do |exdate|
        Array(exdate).each do |date|
          parsed = parse_datetime(date)
          schedule.add_exception_time(parsed) if parsed
        end
      end
    end

    schedule.to_yaml
  rescue StandardError => e
    Rails.logger.warn("Failed to build IceCube schedule: #{e.message}")
    nil
  end

  def parse_rrule_to_ice_cube(rrule, start_time)
    # Extract RRULE components
    freq = extract_rrule_param(rrule, :frequency) || extract_rrule_param(rrule, :freq)
    return nil unless freq

    rule = case freq.to_s.upcase
    when "DAILY"
      IceCube::Rule.daily
    when "WEEKLY"
      IceCube::Rule.weekly
    when "MONTHLY"
      IceCube::Rule.monthly
    when "YEARLY"
      IceCube::Rule.yearly
    else
      return nil
    end

    # Interval
    interval = extract_rrule_param(rrule, :interval)
    rule = rule.interval(interval.to_i) if interval.to_i > 1

    # Count
    count = extract_rrule_param(rrule, :count)
    rule = rule.count(count.to_i) if count

    # Until
    until_date = extract_rrule_param(rrule, :until)
    if until_date
      parsed_until = parse_datetime(until_date)
      rule = rule.until(parsed_until) if parsed_until
    end

    # By day (for weekly)
    byday = extract_rrule_param(rrule, :by_day) || extract_rrule_param(rrule, :byday)
    if byday.present?
      days = Array(byday).map { |d| day_symbol(d) }.compact
      rule = rule.day(*days) if days.any?
    end

    # By month day
    bymonthday = extract_rrule_param(rrule, :by_month_day) || extract_rrule_param(rrule, :bymonthday)
    if bymonthday.present?
      days = Array(bymonthday).map(&:to_i)
      rule = rule.day_of_month(*days) if days.any?
    end

    # By month
    bymonth = extract_rrule_param(rrule, :by_month) || extract_rrule_param(rrule, :bymonth)
    if bymonth.present?
      months = Array(bymonth).map(&:to_i)
      rule = rule.month_of_year(*months) if months.any?
    end

    rule
  rescue StandardError => e
    Rails.logger.warn("Failed to parse RRULE: #{e.message}")
    nil
  end

  def extract_rrule_param(rrule, param)
    if rrule.respond_to?(param)
      rrule.send(param)
    elsif rrule.respond_to?(:[])
      rrule[param] || rrule[param.to_s.upcase]
    else
      nil
    end
  end

  def day_symbol(day_str)
    day_map = {
      "SU" => :sunday,
      "MO" => :monday,
      "TU" => :tuesday,
      "WE" => :wednesday,
      "TH" => :thursday,
      "FR" => :friday,
      "SA" => :saturday
    }

    # Handle cases like "1MO" (first Monday) - extract just the day part
    day_code = day_str.to_s.upcase.gsub(/[^A-Z]/, "")
    day_map[day_code]
  end
end

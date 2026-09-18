# frozen_string_literal: true

require "icalendar"

module Caldav
  # The iCalendar object for one event, as CalDAV servers store it: no METHOD (RFC 4791),
  # times in UTC, and the exceptions of a synced series kept as they were.
  class EventIcalendar
    def initialize(event)
      @event = event
    end

    def to_ical
      build_icalendar(@event)
    end

    private

    def build_icalendar(event)
      cal = Icalendar::Calendar.new
      cal.prodid = "-//#{Rails.application.config.x.app.name}//Calendar//EN"

      vevent = Icalendar::Event.new
      vevent.uid = event.uid
      vevent.summary = event.summary
      vevent.description = event.description if event.description.present?
      vevent.location = event.location if event.location.present?

      if event.all_day?
        vevent.dtstart = Icalendar::Values::Date.new(event.first_day)
        vevent.dtend = Icalendar::Values::Date.new(event.last_day + 1)
      else
        vevent.dtstart = utc_value(event.starts_at)
        vevent.dtend = utc_value(event.ends_at)
      end

      vevent.status = event.status.upcase if event.status.present?

      if event.is_recurring? && event.rrule.present?
        vevent.rrule = [ Icalendar::Values::Recur.new(event.rrule) ]
      end

      if event.organizer_email.present?
        vevent.organizer = Icalendar::Values::CalAddress.new("mailto:#{event.organizer_email}",
          { "cn" => event.organizer_name.presence }.compact)
      end

      event.attendees.each do |attendee|
        vevent.append_attendee Icalendar::Values::CalAddress.new("mailto:#{attendee["email"]}",
          { "cn" => attendee["name"].presence, "partstat" => attendee["status"].presence&.upcase || "NEEDS-ACTION" }.compact)
      end

      vevent.dtstamp = utc_value(Time.current)

      cal.add_event(vevent)
      keep_exceptions(cal, vevent, event) if event.is_recurring? && event.rrule.present?
      cal.to_ical
    end

    def utc_value(time)
      Icalendar::Values::DateTime.new(time.utc, "tzid" => "UTC")
    end

    def keep_exceptions(cal, vevent, event)
      original = Icalendar::Calendar.parse(event.raw_icalendar.to_s).first
      return unless original

      same_event = original.events.select { |component| component.uid.to_s == event.uid }
      series = same_event.find { |component| component.recurrence_id.nil? }
      return unless series && same_start?(series, event)

      vevent.exdate = series.exdate
      vevent.rdate = series.rdate
      same_event.select(&:recurrence_id).each { |occurrence| cal.add_event(occurrence) }
      original.timezones.each { |timezone| cal.add_timezone(timezone) }
    rescue Icalendar::Parser::ParseError, ArgumentError => e
      Rails.logger.warn("Couldn't keep the exceptions of event #{event.uid}: #{e.message}")
    end

    def same_start?(series, event)
      if event.all_day?
        series.dtstart.is_a?(Icalendar::Values::Date) && series.dtstart.to_date == event.first_day
      else
        !series.dtstart.is_a?(Icalendar::Values::Date) && series.dtstart.to_time == event.starts_at
      end
    end
  end
end

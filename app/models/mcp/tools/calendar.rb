# frozen_string_literal: true

module Mcp
  module Tools
    module Calendar
      extend Declaring

      FIELDS = %i[description location all_day].freeze
      RECURRENCE = {
        repeat: :recurrence_frequency, repeat_every: :recurrence_interval, repeat_on: :recurrence_days_of_week,
        repeat_monthly_by: :recurrence_monthly_by, repeat_ends: :recurrence_end_type, repeat_count: :recurrence_count,
        repeat_until: :recurrence_until
      }.freeze

      def self.appointment_params
        {
          title: text("What it is"),
          starts: text("When it starts: 2026-09-18 14:00 in your time zone, or with an offset (2026-09-18T14:00:00+02:00)"),
          ends: text("When it ends, written the same way. An all-day appointment ends at the end of its last day, e.g. 2026-10-06 23:59:59"),
          all_day: flag("All day: only the days count"),
          location: text("Where, plain text"),
          description: text("Notes, plain text"),
          calendar: text("The calendar's id or name (the default calendar without one)"),
          repeat: choice(%w[daily weekly monthly yearly none], "How it repeats, or none to stop"),
          repeat_every: number("Every N days, weeks, months or years (default 1)"),
          repeat_on: list({ type: "string", enum: %w[MO TU WE TH FR SA SU] }, "Weekly: on these days"),
          repeat_monthly_by: choice(%w[day_of_month day_of_week], "Monthly: on the same date, or the same weekday (the 3rd Friday)"),
          repeat_ends: choice(%w[never count until], "When the repeating stops"),
          repeat_count: number("With repeat_ends count: how many times"),
          repeat_until: date("With repeat_ends until: the last day")
        }
      end

      def self.attributes(call)
        call.instance_exec do
          attributes = { summary: arg(:title), start_time: arg(:starts), end_time: arg(:ends) }.compact
          FIELDS.each { attributes[it] = arg(it) if given?(it) }
          RECURRENCE.each { |name, field| attributes[field] = arg(name) if given?(name) }
          if arg(:calendar)
            calendars = get("/tools/#{arg(:tool_id)}/calendar")["calendars"]
            attributes[:calendar_id] = named(calendars, arg(:calendar), "name", "calendar")["id"]
          end
          attributes
        end
      end

      def self.appointment
        { tool_id: tool_id("calendar"), appointment_id: id("The appointment's id", required: true) }
      end

      def self.path(call)
        "/tools/#{call.arg(:tool_id)}/calendar/events/#{call.arg(:appointment_id)}"
      end

      tool "appointment_list", "Show a calendar",
        "A calendar tool's calendars (with how their sync is doing) and its appointments from start_date through " \
        "end_date (both included; 92 days at most). Without dates: today and the six days after.",
        params: {
          tool_id: tool_id("calendar"),
          start_date: date("The first day"),
          end_date: date("The last day")
        }, read_only: true do
        get "/tools/#{arg(:tool_id)}/calendar", start_date: arg(:start_date), end_date: arg(:end_date)
      end

      tool "appointment_show", "Show an appointment",
        "One appointment: its time, place, notes, how it repeats, and for an invitation its organizer and attendees.",
        params: appointment, read_only: true do
        get Calendar.path(self)
      end

      tool "appointment_create", "Make an appointment",
        "Puts an appointment in a calendar, sends it to the calendar's server and tells the tool's other people.",
        params: { tool_id: tool_id("calendar") }.merge(appointment_params)
          .merge(title: text("What it is", required: true), starts: text("When it starts (see appointment_update)", required: true),
                 ends: text("When it ends (see appointment_update)", required: true)) do
        post "/tools/#{arg(:tool_id)}/calendar/events", calendars_event: Calendar.attributes(self)
      end

      tool "appointment_update", "Change an appointment",
        "Changes an appointment. A repeating one is one series: a change is to every occurrence, and a new start moves " \
        "the series.",
        params: appointment.merge(appointment_params) do
        attributes = Calendar.attributes(self)
        raise Tool::Error, "Nothing to change" if attributes.empty?

        patch Calendar.path(self), calendars_event: attributes
      end

      tool "appointment_delete", "Delete an appointment",
        "Deletes an appointment, here and on the calendar's server; a repeating one with every occurrence.",
        params: appointment, destructive: true do
        delete Calendar.path(self)
      end

      tool "calendar_sync", "Sync a calendar",
        "Starts fetching a calendar tool's appointments from its server now (it happens every 15 minutes anyway). " \
        "appointment_list shows when it is done.",
        params: { tool_id: tool_id("calendar") } do
        post "/tools/#{arg(:tool_id)}/calendar/sync"
      end
    end
  end
end

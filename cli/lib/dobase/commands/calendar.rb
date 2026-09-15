# frozen_string_literal: true

module Dobase
  module Commands
    class Calendar < Command
      FREQUENCIES = %w[daily weekly monthly yearly].freeze
      EVENT_FLAGS = {
        start: [ "TIME", "Start: \"YYYY-MM-DD HH:MM\" in your Dobase time zone (a date with --all-day)" ],
        end: [ "TIME", "End, like --start (default: --duration after the start)" ],
        duration: [ "DURATION", "Length instead of --end: 30m, 1h, 1h30m (default 1h)" ],
        all_day: [ nil, "All-day event: --start and --end are dates (--end defaults to --start)" ],
        location: [ "TEXT", "Location" ],
        description: [ "TEXT", "Description (plain text)" ],
        calendar: [ "CALENDAR", "Calendar id or name (default: the default calendar)" ],
        repeat: [ "FREQUENCY", "Repeat #{FREQUENCIES.join(", ")}, or none to stop repeating" ],
        repeat_until: [ "DATE", "Repeat until this date (YYYY-MM-DD)" ],
        repeat_count: [ "N", "Repeat N times" ]
      }.freeze
      UPDATE_FLAGS = EVENT_FLAGS.merge(
        title: [ "TEXT", "New title" ],
        end: [ "TIME", "New end, like --start (a new --start alone keeps the length)" ],
        duration: [ "DURATION", "New length instead of --end: 30m, 1h, 1h30m" ],
        calendar: [ "CALENDAR", "Move to this calendar (id or name)" ]
      ).freeze
      TIME_PATTERN = /\A(\d{4}-\d{2}-\d{2}|today|tomorrow)(?:[ T](\d{1,2}):(\d{2}))?\z/
      DURATION_PATTERN = /\A(?:(\d+)h)?(?:(\d+)m)?\z/
      SYNC_TIMEOUT = 60

      noun "event", "Events in a calendar (calendar tools)"
      noun "calendar", "The calendars of a calendar tool, and syncing them"

      command "event list", "List events by day: today and the next 6 days, unless you pick the days", args: %w[TOOL],
        flags: {
          from: [ "DATE", "First day: YYYY-MM-DD, today or tomorrow (default: today)" ],
          to: [ "DATE", "Last day, included" ],
          days: [ "N", "Number of days, instead of --to" ]
        } do |ref, from: nil, to: nil, days: nil|
        raise UsageError, "Use --to or --days, not both." if to && days

        calendar_tool = tool(ref, "calendar")
        first_day = from && day_param(from)
        last_day = to && day_param(to)
        if days
          first_day ||= Date.today
          last_day = first_day + positive_integer(days, "--days") - 1
        end

        agenda = get("/tools/#{calendar_tool["id"]}/calendar", start_date: first_day&.iso8601, end_date: last_day&.iso8601)

        output(agenda) do
          first_day = Date.iso8601(agenda["start_date"])
          say "#{calendar_tool["name"]} (calendar #{calendar_tool["id"]}): #{full_day(first_day)} to #{full_day(Date.iso8601(agenda["end_date"]))}"
          say "  (no events)" if agenda["events"].empty?

          # Events that began before the first day are listed under it.
          agenda["events"].each_with_index.group_by { |event, _| [ date_of(event["starts_at"]), first_day ].max }.each do |listed_on, entries|
            say
            say listed_on.strftime("%A %-d %B %Y")
            table(entries.sort_by { |event, index| [ event["all_day"] ? 0 : 1, index ] }.map { |event, _|
              [ time_range(event, listed_on), "#{calendar_tool["id"]}/#{event["id"]}", event["summary"], event_details(event) ]
            })
          end
        end
      end

      command "event show", "Show an event; a repeating event shows as its whole series", args: %w[TOOL/EVENT] do |ref|
        calendar_tool, id = tool_and_id(ref, "calendar", "event")
        event = get("/tools/#{calendar_tool["id"]}/calendar/events/#{id}")

        output(event) do
          say "#{event["summary"]} (event #{calendar_tool["id"]}/#{event["id"]})"
          field "When", event_span(event)
          field "Repeats", event["recurrence"]
          field "Calendar", event.dig("calendar", "name")
          field "Location", event["location"]
          field "Status", event["status"]
          field "Organizer", organizer(event["organizer"])
          field "Created by", person(event["creator"])
          field "URL", event["url"]

          unless event["description"].to_s.strip.empty?
            say
            say "Description:"
            paragraph event["description"]
          end

          unless event["attendees"].empty?
            say
            say "Attendees (#{event["attendees"].size}):"
            table(event["attendees"].map { |attendee| [ organizer(attendee), attendee["status"] ] })
          end
        end
      end

      command "event create", "Add an event to a calendar tool", args: %w[TOOL TITLE], flags: EVENT_FLAGS do |ref, title, **options|
        raise UsageError, "--start is required. See `dobase help event`." unless options[:start]

        calendar_tool = tool(ref, "calendar")
        attributes = event_attributes(calendar_tool, options, creating: true).merge(summary: title)
        event = post("/tools/#{calendar_tool["id"]}/calendar/events", calendars_event: attributes)

        output(event) do
          say "Created event #{calendar_tool["id"]}/#{event["id"]} #{quoted(event["summary"])} in #{event.dig("calendar", "name")}: #{event_span(event)}"
          field "Repeats", event["recurrence"]
        end
      end

      command "event update", "Change an event; for a repeating event this changes the whole series", args: %w[TOOL/EVENT],
        flags: UPDATE_FLAGS do |ref, title: nil, **options|
        calendar_tool, id = tool_and_id(ref, "calendar", "event")
        path = "/tools/#{calendar_tool["id"]}/calendar/events/#{id}"

        changes_timing = options.values_at(:start, :end, :duration, :all_day).any?
        changes_repeat_end = (options[:repeat_until] || options[:repeat_count]) && options[:repeat].nil?
        current = get(path) if changes_timing || changes_repeat_end
        if changes_repeat_end && !current["recurring"]
          raise UsageError, "Event #{calendar_tool["id"]}/#{id} doesn't repeat. Add --repeat FREQUENCY."
        end

        attributes = event_attributes(calendar_tool, options, current: current)
        attributes[:summary] = title if title
        raise UsageError, "Nothing to update. See `dobase help event`." if attributes.empty?

        event = patch(path, calendars_event: attributes)
        output(event) do
          say "Updated event #{calendar_tool["id"]}/#{event["id"]} #{quoted(event["summary"])} in #{event.dig("calendar", "name")}: #{event_span(event)}"
          field "Repeats", event["recurrence"]
        end
      end

      command "event delete", "Delete an event; for a repeating event, every occurrence", args: %w[TOOL/EVENT] do |ref|
        calendar_tool, id = tool_and_id(ref, "calendar", "event")
        delete("/tools/#{calendar_tool["id"]}/calendar/events/#{id}")
        output(nil) { say "Deleted event #{calendar_tool["id"]}/#{id}." }
      end

      command "calendar list", "List the calendars of a calendar tool and its sync status", args: %w[TOOL] do |ref|
        calendar_tool = tool(ref, "calendar")
        overview = calendar_overview(calendar_tool)

        output(overview) do
          say "#{calendar_tool["name"]} (calendar #{calendar_tool["id"]})"
          field "Sync", sync_summary(overview)
          say
          table(overview["calendars"].map { |calendar| [ calendar["id"], calendar["name"], calendar["color"], calendar_flags(calendar) ] })
        end
      end

      command "calendar sync", "Sync a calendar tool with its CalDAV server and wait up to a minute for it", args: %w[TOOL] do |ref|
        calendar_tool = tool(ref, "calendar")
        path = "/tools/#{calendar_tool["id"]}/calendar/sync"

        status = post(path)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SYNC_TIMEOUT
        while status["status"] == "syncing" && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          sleep 1
          status = get(path)
        end

        output(status) do
          name = "#{calendar_tool["name"]} (calendar #{calendar_tool["id"]})"
          case status["status"]
          when "synced" then say "Synced #{name} at #{moment(status["last_synced_at"])}."
          when "syncing" then say "#{name} is still syncing. Check later with `dobase calendar list #{calendar_tool["id"]}`."
          else raise Error, "Syncing #{name} failed. Check its calendar account in the browser."
          end
        end
      end

      private

      # The calendar for a single day: enough for its calendars and sync status.
      def calendar_overview(calendar_tool)
        today = Date.today.iso8601
        get("/tools/#{calendar_tool["id"]}/calendar", start_date: today, end_date: today)
      end

      def find_calendar(calendar_tool, ref)
        calendars = calendar_overview(calendar_tool)["calendars"]
        match = calendars.find { |calendar| calendar["id"].to_s == ref } ||
          calendars.find { |calendar| calendar["name"].casecmp?(ref) } ||
          calendars.find { |calendar| calendar["name"].downcase.start_with?(ref.downcase) }
        match || raise(Error, "No calendar matches #{quoted(ref)}. Calendars: #{calendars.map { |calendar| calendar["name"] }.join(", ")}")
      end

      # -- Input ---------------------------------------------------------------

      def event_attributes(calendar_tool, options, current: nil, creating: false)
        attributes = timing_attributes(options, current)
        attributes[:location] = text(options[:location]) if options[:location]
        attributes[:description] = text(options[:description]).rstrip if options[:description]
        attributes[:calendar_id] = find_calendar(calendar_tool, options[:calendar])["id"] if options[:calendar]
        attributes.merge(recurrence_attributes(options, creating: creating))
      end

      # start_time, end_time and all_day from --start, --end, --duration and --all-day.
      # When updating, `current` is the event: what isn't given stays as it is, and
      # a new start keeps the event's length.
      def timing_attributes(options, current)
        return {} unless options.values_at(:start, :end, :duration, :all_day).any?
        raise UsageError, "Use --end or --duration, not both." if options[:end] && options[:duration]

        start = options[:start] && time_param(options[:start], "--start")
        finish = options[:end] && time_param(options[:end], "--end")
        stays_all_day = current && current["all_day"] && [ start, finish ].compact.none? { |value| value[:time] }

        if options[:all_day] || stays_all_day
          all_day_timing(start, finish, options, current)
        else
          timed_timing(start, finish, options, current)
        end
      end

      # All-day events run from the start of the first day to the end of the last.
      def all_day_timing(start, finish, options, current)
        raise UsageError, "--duration doesn't work for all-day events. Use --end DATE." if options[:duration]

        first = start ? start[:date] : date_of(current["starts_at"])
        last = if finish
          finish[:date]
        elsif start && current&.dig("all_day")
          first + (date_of(current["ends_at"]) - date_of(current["starts_at"]))
        elsif start
          first
        else
          [ date_of(current["ends_at"]), first ].max
        end
        raise UsageError, "--end is before the start." if last < first

        attributes = { all_day: true, end_time: "#{last.iso8601} 23:59:59" }
        attributes[:start_time] = "#{first.iso8601} 00:00" if start || !current&.dig("all_day")
        attributes
      end

      def timed_timing(start, finish, options, current)
        [ start, finish ].compact.each do |value|
          raise UsageError, "#{value[:flag]} needs a time, like \"2026-10-01 14:30\", or add --all-day." unless value[:time]
        end

        starts = start ? wall_clock(start) : wall_clock_of(current["starts_at"])
        ends = if finish
          wall_clock(finish)
        elsif options[:duration]
          starts + duration_seconds(options[:duration])
        elsif current && !current["all_day"]
          starts + (wall_clock_of(current["ends_at"]) - wall_clock_of(current["starts_at"]))
        else
          starts + 3600
        end
        raise UsageError, "--end is before the start." if ends < starts

        attributes = { all_day: false, end_time: clock_param(ends) }
        attributes[:start_time] = clock_param(starts) if start || current.nil? || current["all_day"]
        attributes
      end

      def recurrence_attributes(options, creating:)
        repeat, repeat_until, repeat_count = options.values_at(:repeat, :repeat_until, :repeat_count)
        return {} unless repeat || repeat_until || repeat_count

        raise UsageError, "Use --repeat-until or --repeat-count, not both." if repeat_until && repeat_count
        raise UsageError, "--repeat must be one of: #{FREQUENCIES.join(", ")}, none" if repeat && !(FREQUENCIES + [ "none" ]).include?(repeat)
        raise UsageError, "--repeat none can't have --repeat-until or --repeat-count." if repeat == "none" && (repeat_until || repeat_count)
        raise UsageError, "--repeat-until and --repeat-count need --repeat." if creating && repeat.nil?

        attributes = repeat ? { recurrence_frequency: repeat } : {}
        if repeat_until
          attributes.merge(recurrence_end_type: "until", recurrence_until: day_param(repeat_until).iso8601)
        elsif repeat_count
          attributes.merge(recurrence_end_type: "count", recurrence_count: positive_integer(repeat_count, "--repeat-count"))
        elsif repeat == "none"
          attributes
        else
          attributes.merge(recurrence_end_type: "never")
        end
      end

      # "YYYY-MM-DD HH:MM" or a date alone; today and tomorrow work too.
      def time_param(value, flag)
        match = TIME_PATTERN.match(value.to_s.strip)
        raise UsageError, "#{flag} expects \"YYYY-MM-DD HH:MM\", got #{quoted(value)}." unless match
        raise UsageError, "#{flag} has an invalid time: #{quoted(value)}." if match[2] && (match[2].to_i > 23 || match[3].to_i > 59)

        { flag: flag, date: day_param(match[1]), time: match[2] && format("%02d:%s", match[2].to_i, match[3]) }
      end

      def day_param(value)
        date = date_param(value)
        raise UsageError, "Expected a date like 2026-10-01, today or tomorrow; got #{quoted(value)}." unless date

        Date.iso8601(date)
      end

      def duration_seconds(value)
        match = DURATION_PATTERN.match(value.to_s.strip.downcase)
        seconds = match ? (match[1].to_i * 3600) + (match[2].to_i * 60) : 0
        raise UsageError, "--duration expects a length like 30m, 1h or 1h30m, got #{quoted(value)}." unless seconds.positive?

        seconds
      end

      def positive_integer(value, flag)
        number = Integer(value, 10, exception: false)
        raise UsageError, "#{flag} expects a positive number, got #{quoted(value)}." unless number&.positive?

        number
      end

      # Times are wall-clock times in the user's Dobase time zone. They are held in
      # UTC Time objects only to do arithmetic on them.
      def wall_clock(time) = Time.utc(time[:date].year, time[:date].month, time[:date].day, *time[:time].split(":").map(&:to_i))
      def wall_clock_of(timestamp) = Time.utc(*timestamp[0, 16].scan(/\d+/).map(&:to_i))
      def clock_param(time) = time.strftime("%Y-%m-%d %H:%M")

      # -- Output --------------------------------------------------------------

      def date_of(timestamp) = Date.iso8601(timestamp[0, 10])
      def clock(timestamp) = timestamp[11, 5]
      def short_day(date) = date.strftime("%a %-d %b")
      def full_day(date) = date.strftime("%a %-d %b %Y")

      def event_span(event)
        starts_on = date_of(event["starts_at"])
        ends_on = date_of(event["ends_at"])

        if event["all_day"]
          ends_on > starts_on ? "#{full_day(starts_on)} to #{full_day(ends_on)}, all day" : "#{full_day(starts_on)}, all day"
        elsif ends_on == starts_on
          "#{full_day(starts_on)} #{clock(event["starts_at"])}–#{clock(event["ends_at"])}"
        else
          "#{full_day(starts_on)} #{clock(event["starts_at"])} to #{full_day(ends_on)} #{clock(event["ends_at"])}"
        end
      end

      # The time of an event listed under `listed_on`.
      def time_range(event, listed_on)
        starts_on = date_of(event["starts_at"])
        ends_on = date_of(event["ends_at"])

        if event["all_day"]
          ends_on > listed_on ? "all day until #{short_day(ends_on)}" : "all day"
        else
          from = starts_on == listed_on ? clock(event["starts_at"]) : "#{short_day(starts_on)} #{clock(event["starts_at"])}"
          till = ends_on == starts_on ? clock(event["ends_at"]) : "#{short_day(ends_on)} #{clock(event["ends_at"])}"
          "#{from}–#{till}"
        end
      end

      def event_details(event)
        [
          event.dig("calendar", "name"),
          (event["location"] unless event["location"].to_s.empty?),
          ("repeats" if event["recurring"]),
          (event["status"] if %w[tentative cancelled].include?(event["status"]))
        ].compact.join(" · ")
      end

      def organizer(contact)
        contact && [ contact["name"], contact["email"] && "<#{contact["email"]}>" ].compact.join(" ")
      end

      def sync_summary(overview)
        return "none, events are kept in Dobase" if overview["local"]

        "#{overview.dig("sync", "status")}, last synced #{moment(overview.dig("sync", "last_synced_at")) || "never"}"
      end

      def calendar_flags(calendar)
        [
          ("default" if calendar["is_default"]),
          ("read-only" if calendar["read_only"]),
          ("disabled" unless calendar["enabled"])
        ].compact.join(", ")
      end
    end
  end
end

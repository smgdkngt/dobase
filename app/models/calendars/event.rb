# frozen_string_literal: true

module Calendars
  class Event < ApplicationRecord
    include Trackable
    self.table_name = "calendar_events"

    # The title of synced events and invitations that come without one (SUMMARY is optional in iCalendar)
    UNTITLED = "(No title)"

    belongs_to :calendar, class_name: "Calendars::Calendar"
    has_one :account, through: :calendar

    # Aliases for cleaner view access
    alias_attribute :start_time, :starts_at
    alias_attribute :end_time, :ends_at

    # Virtual attributes for recurrence form
    attr_accessor :recurrence_frequency,    # "none", "daily", "weekly", "monthly", "yearly"
                  :recurrence_interval,     # integer >= 1
                  :recurrence_days_of_week, # array of day abbreviations: ["MO", "WE", "FR"]
                  :recurrence_monthly_by,   # "day_of_month" or "day_of_week"
                  :recurrence_end_type,     # "never", "count", "until"
                  :recurrence_count,        # integer
                  :recurrence_until         # date string

    # What a listener outside the browser hears changed (Event), by the name it hears it under:
    # when, what and where. The rest (attendees, what the server keeps) changes too often to say.
    TOLD_CHANGES = { "summary" => "title", "starts_at" => "starts_at", "ends_at" => "ends_at", "all_day" => "all_day",
                     "location" => "location", "calendar_id" => "calendar" }.freeze

    # Alerts, as minutes before the start (Calendars::Reminder): written to the calendar's server
    # as VALARMs, given by the calendar app on someone's phone or computer
    serialize :reminders, coder: JSON

    before_validation :pin_all_day_to_dates, if: :all_day_times_to_pin?
    before_validation :resolve_reminders
    before_validation :build_recurrence_from_form, if: :recurrence_frequency_provided?

    # Made, changed or removed here, through the API or by a sync: each is an event, unless
    # nothing that is told changed. A calendar's first sync is quiet (CaldavSyncService).
    after_create { record_event(:created) }
    after_update do
      changed = TOLD_CHANGES.filter_map { |attribute, told| told if saved_change_to_attribute?(attribute) }
      record_event(:updated, changed: changed) if changed.any?
    end
    after_destroy { record_event(:deleted) }

    validates :uid, presence: true
    validates :summary, presence: true
    validates :starts_at, presence: true
    validates :ends_at, presence: true
    validate :ends_at_after_starts_at
    validate :reminders_readable

    scope :in_range, ->(start_date, end_date) {
      where("starts_at < ? AND ends_at > ?", end_date, start_date)
    }
    # Timed events on these days in the current time zone, and all-day events on these dates
    scope :during, ->(first_day, last_day) {
      where(all_day: [ false, nil ]).in_range(first_day.beginning_of_day, last_day.end_of_day)
        .or(where(all_day: true).in_range(first_day.to_time(:utc), (last_day + 1).to_time(:utc)))
    }
    scope :recurring, -> { where(is_recurring: true) }
    scope :non_recurring, -> { where(is_recurring: false) }
    scope :by_start, -> { order(starts_at: :asc) }

    STATUSES = %w[tentative confirmed cancelled].freeze

    validates :status, inclusion: { in: STATUSES }, allow_nil: true

    # Nil until they were read or set: an event synced before Dobase kept alerts has them only in
    # what the server sent, and is changed here with those, not without them.
    def reminders
      stored = super
      return stored if stored
      return [] unless raw_icalendar.to_s.include?("BEGIN:VALARM")

      @reminders_from_server ||= IcsParserService.new(raw_icalendar).parse[:reminders]
    end

    # What someone wrote (75, "45m", "1d@17:00", blanks for none) is read when the event is
    # validated, once its start is known: a time on a day before counts from that start.
    def reminders=(values)
      @reminders_written = values.nil? ? [] : Array(values)
      super(@reminders_written)
    end

    def reminder_list
      reminders.map { |minutes| { minutes: minutes, label: Calendars::Reminder.label(minutes, starts_at: starts_at, all_day: all_day?) } }
    end

    # Populate virtual attributes from existing RRULE for editing
    def load_recurrence_for_form
      self.recurrence_interval ||= 1
      self.recurrence_days_of_week ||= []
      self.recurrence_monthly_by ||= "day_of_month"
      self.recurrence_end_type ||= "never"

      if rrule.blank?
        self.recurrence_frequency = "none"
        return
      end

      parts = parse_rrule_parts
      self.recurrence_frequency = parts[:freq]&.downcase || "none"
      self.recurrence_interval = parts[:interval] || 1
      self.recurrence_days_of_week = extract_days_from_rrule(parts)
      self.recurrence_monthly_by = parts[:bymonthday].present? ? "day_of_month" : "day_of_week"
      self.recurrence_end_type = if parts[:count]
        "count"
      elsif parts[:until]
        "until"
      else
        "never"
      end
      self.recurrence_count = parts[:count]
      self.recurrence_until = parse_until_date(parts[:until])
    end

    # Whether this RRULE can be edited in the form (no exotic features)
    def recurrence_editable?
      return true if rrule.blank?
      parts = parse_rrule_parts
      unsupported = parts.keys - %i[freq interval byday bymonthday count until]
      unsupported.empty?
    end

    # Human-readable recurrence description, in the page's language (English for the API)
    def recurrence_description
      return nil unless is_recurring? && rrule.present?
      parts = parse_rrule_parts
      freq = parts[:freq]&.downcase
      interval = (parts[:interval] || 1).to_i

      desc = case freq
      when "daily"
        interval == 1 ? _("Daily") : _("Every %{count} days", count: interval)
      when "weekly"
        base = interval == 1 ? _("Weekly") : _("Every %{count} weeks", count: interval)
        if parts[:byday].present?
          day_names = parts[:byday].split(",").filter_map { |d| day_full_name(d) }
          day_names.any? ? _("%{base} on %{days}", base: base, days: day_names.map { |name| _(name) }.join(I18n.t("support.array.words_connector"))) : base
        else
          base
        end
      when "monthly"
        base = interval == 1 ? _("Monthly") : _("Every %{count} months", count: interval)
        if parts[:bymonthday].present?
          _("%{base} on day %{day}", base: base, day: Translation.digits(parts[:bymonthday]))
        elsif parts[:byday].present?
          _("%{base} on %{days}", base: base, days: ordinal_day_description(parts[:byday]))
        else
          base
        end
      when "yearly"
        interval == 1 ? _("Yearly") : _("Every %{count} years", count: interval)
      else
        rrule
      end

      if parts[:count].present?
        desc = _("%{description}, %{count} times", description: desc, count: parts[:count].to_i)
      elsif parts[:until].present?
        if (until_date = parse_until_date(parts[:until]))
          desc = _("%{description}, until %{date}", description: desc, date: ApplicationController.helpers.format_date(Date.parse(until_date), year: true))
        end
      end

      desc
    end

    def attendees
      return [] if attendees_json.blank?
      JSON.parse(attendees_json)
    rescue JSON::ParserError
      []
    end

    def attendees=(list)
      self.attendees_json = list.to_json
    end

    # The moved occurrences of a synced series, as the server has them
    def recurrence_overrides
      return [] if recurrence_overrides_json.blank?
      JSON.parse(recurrence_overrides_json)
    rescue JSON::ParserError
      []
    end

    def recurrence_overrides=(list)
      self.recurrence_overrides_json = list.presence&.to_json
    end

    def duration_minutes
      ((ends_at - starts_at) / 60).to_i
    end

    def duration_hours
      duration_minutes / 60.0
    end

    def multi_day?
      starts_at.to_date != ends_at.to_date
    end

    # All-day events are about dates, not times. They run from midnight UTC on their first day
    # to midnight UTC after their last, like dates in iCalendar, so they fall on the same days
    # in every time zone.
    def first_day
      all_day? ? starts_at.utc.to_date : starts_at.to_date
    end

    # An event that ends at midnight ends on the day before
    def last_day
      return ends_at.utc.to_date - 1 if all_day?

      ends_at == ends_at.beginning_of_day && ends_at > starts_at ? ends_at.to_date - 1 : ends_at.to_date
    end

    # The copies Tools::CalendarsController makes for each occurrence of a
    # recurring event answer true.
    def occurrence?
      false
    end

    def record_event(kind, **data)
      ::Event.record("calendar.event_#{kind}", tool: calendar.account.tool, record: self, title: summary,
        starts_at: starts_at&.utc&.iso8601, ends_at: ends_at&.utc&.iso8601, all_day: all_day?,
        location: location.presence, calendar: calendar.name, **data)
    end

    private

    DAY_SYMBOLS = { "SU" => :sunday, "MO" => :monday, "TU" => :tuesday,
                    "WE" => :wednesday, "TH" => :thursday, "FR" => :friday, "SA" => :saturday }.freeze
    DAY_FULL_NAMES = { "MO" => "Monday", "TU" => "Tuesday", "WE" => "Wednesday",
                       "TH" => "Thursday", "FR" => "Friday", "SA" => "Saturday", "SU" => "Sunday" }.freeze
    WDAY_TO_ABBR = %w[SU MO TU WE TH FR SA].freeze

    def all_day_times_to_pin?
      all_day? && starts_at.present? && ends_at.present? &&
        (will_save_change_to_all_day? || will_save_change_to_starts_at? || will_save_change_to_ends_at?)
    end

    # Takes the dates of the given times in the user's time zone. Times at midnight UTC stand for
    # their UTC date already: that's how synced events and invitations arrive. An end at midnight
    # is the start of the day after the event, like DTEND.
    def pin_all_day_to_dates
      starts, ends = [ starts_at, ends_at ].map { |time| time.utc == time.utc.midnight ? time.utc : time }
      ends -= 1.day if ends == ends.midnight && ends > starts

      self.starts_at = starts.to_date.to_time(:utc)
      self.ends_at = (ends.to_date + 1).to_time(:utc)
    end

    def recurrence_frequency_provided?
      recurrence_frequency.present?
    end

    # All-day events repeat on dates, so their schedule runs in UTC like their times
    def recurrence_start
      all_day? ? starts_at.utc : starts_at
    end

    def build_recurrence_from_form
      return clear_recurrence if recurrence_frequency == "none"

      schedule = IceCube::Schedule.new(recurrence_start)

      rule = case recurrence_frequency
      when "daily"  then IceCube::Rule.daily(interval_value)
      when "weekly"  then build_weekly_rule
      when "monthly" then build_monthly_rule
      when "yearly"  then IceCube::Rule.yearly(interval_value)
      else return clear_recurrence
      end

      rule = apply_end_condition(rule)
      schedule.add_recurrence_rule(rule)

      self.is_recurring = true
      self.rrule = build_rrule_string
      self.recurrence_schedule = schedule.to_yaml
    end

    def clear_recurrence
      self.is_recurring = false
      self.rrule = nil
      self.recurrence_schedule = nil
    end

    def interval_value
      (recurrence_interval.presence || 1).to_i.clamp(1, 99)
    end

    def build_weekly_rule
      rule = IceCube::Rule.weekly(interval_value)
      if recurrence_days_of_week.present?
        days = Array(recurrence_days_of_week).filter_map { |d| day_symbol(d) }
        rule = rule.day(*days) if days.any?
      end
      rule
    end

    def build_monthly_rule
      rule = IceCube::Rule.monthly(interval_value)
      if recurrence_monthly_by == "day_of_week"
        wday = recurrence_start.wday
        week_of_month = ((recurrence_start.day - 1) / 7) + 1
        day_sym = Date::DAYNAMES[wday].downcase.to_sym
        rule.day_of_week(day_sym => [ week_of_month ])
      else
        rule.day_of_month(recurrence_start.day)
      end
    end

    def apply_end_condition(rule)
      case recurrence_end_type
      when "count"
        rule.count(recurrence_count.to_i.clamp(1, 999))
      when "until"
        until_date = Date.parse(recurrence_until)
        rule.until(all_day? ? until_date.to_time(:utc).end_of_day : until_date.end_of_day)
      else
        rule
      end
    rescue ArgumentError, TypeError
      rule
    end

    def build_rrule_string
      parts = [ "FREQ=#{recurrence_frequency.upcase}" ]
      int = interval_value
      parts << "INTERVAL=#{int}" if int > 1

      if recurrence_frequency == "weekly" && Array(recurrence_days_of_week).any?
        parts << "BYDAY=#{Array(recurrence_days_of_week).join(',')}"
      end

      if recurrence_frequency == "monthly"
        # Same default as build_monthly_rule: the day of the month.
        if recurrence_monthly_by == "day_of_week"
          week_num = ((recurrence_start.day - 1) / 7) + 1
          day_abbr = WDAY_TO_ABBR[recurrence_start.wday]
          parts << "BYDAY=#{week_num}#{day_abbr}"
        else
          parts << "BYMONTHDAY=#{recurrence_start.day}"
        end
      end

      case recurrence_end_type
      when "count"
        parts << "COUNT=#{recurrence_count.to_i.clamp(1, 999)}"
      when "until"
        parts << "UNTIL=#{Date.parse(recurrence_until).strftime('%Y%m%dT235959Z')}"
      end

      parts.join(";")
    rescue ArgumentError, TypeError
      parts.join(";")
    end

    def parse_rrule_parts
      return {} if rrule.blank?
      rrule.split(";").each_with_object({}) do |part, hash|
        key, value = part.split("=", 2)
        hash[key.downcase.to_sym] = value
      end
    end

    def extract_days_from_rrule(parts)
      return [] unless parts[:byday].present?
      # Strip ordinal prefixes for monthly (e.g., "2MO" -> "MO")
      parts[:byday].split(",").map { |d| d.gsub(/^\d+/, "") }
    end

    def parse_until_date(until_str)
      return nil if until_str.blank?
      # UNTIL format: 20260630T235959Z or 20260630
      until_str.gsub(/T.*/, "").then { |s| Date.strptime(s, "%Y%m%d").iso8601 }
    rescue ArgumentError, TypeError
      nil
    end

    def day_symbol(abbr)
      DAY_SYMBOLS[abbr.to_s.upcase.gsub(/[^A-Z]/, "")]
    end

    def day_full_name(abbr)
      code = abbr.to_s.upcase.gsub(/[^A-Z]/, "")
      DAY_FULL_NAMES[code]
    end

    def ordinal_day_description(byday)
      if byday =~ /^(\d+)([A-Z]{2})$/
        ordinals = { 1 => _("1st"), 2 => _("2nd"), 3 => _("3rd"), 4 => _("4th"), 5 => _("5th") }
        ordinal = ordinals[$1.to_i] || "#{$1.to_i}th"
        _("the %{ordinal} %{weekday}", ordinal: ordinal, weekday: _(day_full_name($2).to_s))
      else
        byday
      end
    end

    def resolve_reminders
      return unless @reminders_written

      written, @reminders_written = @reminders_written, nil
      @reminder_errors = []
      minutes = written.reject { |value| value.to_s.strip.in?([ "", "none" ]) }.filter_map do |value|
        Calendars::Reminder.parse(value, starts_at: starts_at, all_day: all_day?)
      rescue Calendars::Reminder::Invalid => e
        @reminder_errors << e.message
        nil
      end
      self.reminders = minutes.uniq.sort
      @reminders_written = nil
    end

    def reminders_readable
      Array(@reminder_errors).each { |message| errors.add(:reminders, message) }
      errors.add(:reminders, _("are more than %{limit}", limit: Calendars::Reminder::LIMIT)) if reminders.size > Calendars::Reminder::LIMIT
    end

    def ends_at_after_starts_at
      return unless starts_at && ends_at
      # An all-day event lasts a day at least
      errors.add(:ends_at, _("must be after the start")) if all_day? ? ends_at <= starts_at : ends_at < starts_at
    end
  end
end

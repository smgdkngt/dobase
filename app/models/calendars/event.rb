# frozen_string_literal: true

module Calendars
  class Event < ApplicationRecord
    self.table_name = "calendar_events"

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

    before_validation :build_recurrence_from_form, if: :recurrence_frequency_provided?

    validates :uid, presence: true
    validates :summary, presence: true
    validates :starts_at, presence: true
    validates :ends_at, presence: true
    validate :ends_at_after_starts_at

    scope :in_range, ->(start_date, end_date) {
      where("starts_at < ? AND ends_at > ?", end_date, start_date)
    }
    scope :recurring, -> { where(is_recurring: true) }
    scope :non_recurring, -> { where(is_recurring: false) }
    scope :by_start, -> { order(starts_at: :asc) }

    STATUSES = %w[tentative confirmed cancelled].freeze

    validates :status, inclusion: { in: STATUSES }, allow_nil: true

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

    # Human-readable recurrence description
    def recurrence_description
      return nil unless is_recurring? && rrule.present?
      parts = parse_rrule_parts
      freq = parts[:freq]&.downcase
      interval = (parts[:interval] || 1).to_i

      desc = case freq
      when "daily"
        interval == 1 ? "Daily" : "Every #{interval} days"
      when "weekly"
        base = interval == 1 ? "Weekly" : "Every #{interval} weeks"
        if parts[:byday].present?
          day_names = parts[:byday].split(",").filter_map { |d| day_full_name(d) }
          day_names.any? ? "#{base} on #{day_names.join(', ')}" : base
        else
          base
        end
      when "monthly"
        base = interval == 1 ? "Monthly" : "Every #{interval} months"
        if parts[:bymonthday].present?
          "#{base} on day #{parts[:bymonthday]}"
        elsif parts[:byday].present?
          "#{base} on #{ordinal_day_description(parts[:byday])}"
        else
          base
        end
      when "yearly"
        interval == 1 ? "Yearly" : "Every #{interval} years"
      else
        rrule
      end

      if parts[:count].present?
        desc += ", #{parts[:count]} times"
      elsif parts[:until].present?
        if (until_date = parse_until_date(parts[:until]))
          desc += ", until #{Date.parse(until_date).strftime('%b %d, %Y')}"
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

    def duration_minutes
      ((ends_at - starts_at) / 60).to_i
    end

    def duration_hours
      duration_minutes / 60.0
    end

    def multi_day?
      starts_at.to_date != ends_at.to_date
    end

    private

    DAY_SYMBOLS = { "SU" => :sunday, "MO" => :monday, "TU" => :tuesday,
                    "WE" => :wednesday, "TH" => :thursday, "FR" => :friday, "SA" => :saturday }.freeze
    DAY_FULL_NAMES = { "MO" => "Monday", "TU" => "Tuesday", "WE" => "Wednesday",
                       "TH" => "Thursday", "FR" => "Friday", "SA" => "Saturday", "SU" => "Sunday" }.freeze
    WDAY_TO_ABBR = %w[SU MO TU WE TH FR SA].freeze

    def recurrence_frequency_provided?
      recurrence_frequency.present?
    end

    def build_recurrence_from_form
      return clear_recurrence if recurrence_frequency == "none"

      schedule = IceCube::Schedule.new(starts_at)

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
        wday = starts_at.wday
        week_of_month = ((starts_at.day - 1) / 7) + 1
        day_sym = Date::DAYNAMES[wday].downcase.to_sym
        rule.day_of_week(day_sym => [ week_of_month ])
      else
        rule.day_of_month(starts_at.day)
      end
    end

    def apply_end_condition(rule)
      case recurrence_end_type
      when "count"
        rule.count(recurrence_count.to_i.clamp(1, 999))
      when "until"
        until_date = Date.parse(recurrence_until).end_of_day
        rule.until(until_date)
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
        if recurrence_monthly_by == "day_of_month"
          parts << "BYMONTHDAY=#{starts_at.day}"
        else
          week_num = ((starts_at.day - 1) / 7) + 1
          day_abbr = WDAY_TO_ABBR[starts_at.wday]
          parts << "BYDAY=#{week_num}#{day_abbr}"
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
        ordinals = { 1 => "1st", 2 => "2nd", 3 => "3rd", 4 => "4th", 5 => "5th" }
        ordinal = ordinals[$1.to_i] || "#{$1.to_i}th"
        day = day_full_name($2)
        "the #{ordinal} #{day}"
      else
        byday
      end
    end

    def ends_at_after_starts_at
      return unless starts_at && ends_at
      errors.add(:ends_at, "must be after starts_at") if ends_at < starts_at
    end
  end
end

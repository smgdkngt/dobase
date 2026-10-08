# frozen_string_literal: true

module Tools
  class CalendarsController < ApplicationController
    include ToolScoped

    # The longest date range the JSON API returns; any three calendar months fit.
    MAX_RANGE_DAYS = 92

    class InvalidDateRange < StandardError; end

    allow_access_tokens
    before_action :require_calendar_account

    def show
      @calendar_account = @tool.calendar_account
      @calendars = @calendar_account.calendars.enabled.by_position

      respond_to do |format|
        format.html { load_week }
        # A form on the calendar page comes back here after its redirect and gets a stream
        # that refreshes the page where it is. A redirect that names a week wants that week
        # shown, so it gets the page itself, which Turbo visits.
        format.turbo_stream { load_week } unless params[:week_start].present?
        format.json { load_date_range }
      end
    end

    private

    def require_calendar_account
      return if @tool.calendar_account

      if request.format.json?
        render json: { error: "Calendar account not configured" }, status: :not_found
      elsif @tool.owned_by?(current_user)
        redirect_to new_tool_calendar_account_path(@tool)
      else
        render "tools/account_not_connected"
      end
    end

    def load_week
      # Calculate week range
      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      # Fetch events for the week
      @events = fetch_events_for_range(@week_start, @week_end)

      # Group events by day
      @events_by_day = group_events_by_day(@events, @week_start, @week_end)
    end

    # start_date through end_date (inclusive), by default today and the six days after.
    def load_date_range
      @start_date = date_param(:start_date) || Date.current
      @end_date = date_param(:end_date) || @start_date + 6.days

      if @end_date < @start_date
        raise InvalidDateRange, "end_date can't be before start_date"
      elsif (@end_date - @start_date).to_i >= MAX_RANGE_DAYS
        raise InvalidDateRange, "The date range can't be longer than #{MAX_RANGE_DAYS} days"
      end

      @events = fetch_events_for_range(@start_date, @end_date)
    rescue InvalidDateRange => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def date_param(name)
      Date.iso8601(params[name].to_s) if params[name].present?
    rescue Date::Error
      raise InvalidDateRange, "#{name} must be a date like #{Date.current.iso8601}"
    end

    def parse_week_start(week_param)
      if week_param.present?
        Date.parse(week_param).beginning_of_week(:monday)
      else
        Date.current.beginning_of_week(:monday)
      end
    rescue ArgumentError
      Date.current.beginning_of_week(:monday)
    end

    def fetch_events_for_range(start_date, end_date)
      base_events = @calendar_account.events
        .joins(:calendar)
        .where(calendar_calendars: { enabled: true })
        .by_start

      events = []

      # Non-recurring events in range
      non_recurring = base_events
        .non_recurring
        .during(start_date, end_date)
        .includes(:calendar)

      events.concat(non_recurring.to_a)

      # Recurring events - expand occurrences
      recurring = base_events.recurring.includes(:calendar)

      recurring.find_each do |event|
        occurrences = expand_recurrence(event, start_date, end_date)
        events.concat(occurrences)
      end

      # All-day events first on their day
      events.sort_by { |event| [ event.first_day, event.all_day? ? 0 : 1, event.starts_at ] }
    end

    def expand_recurrence(event, start_date, end_date)
      return [] unless event.recurrence_schedule.present?

      schedule = IceCube::Schedule.from_yaml(event.recurrence_schedule)
      duration = event.ends_at - event.starts_at

      # Occurrences of all-day events start at midnight UTC on their dates
      first, last = if event.all_day?
        [ start_date.to_time(:utc), (end_date + 1).to_time(:utc) - 1 ]
      else
        [ start_date.beginning_of_day, end_date.end_of_day ]
      end

      occurrences = schedule.occurrences_between(first, last).map do |occurrence_start|
        occurrence_of(event, occurrence_start, occurrence_start + duration)
      end

      # Moved occurrences are listed at their new time, wherever they were moved from
      moved = event.recurrence_overrides.filter_map do |override|
        starts_at = Time.zone.parse(override["starts_at"])
        next unless starts_at.between?(first, last)

        occurrence_of(event, starts_at, Time.zone.parse(override["ends_at"]),
          **override.slice("summary", "description", "location").compact_blank.symbolize_keys)
      end

      occurrences + moved
    rescue StandardError => e
      Rails.logger.warn("Failed to expand recurrence for event #{event.id}: #{e.message}")
      []
    end

    # A virtual event for one occurrence of a series, with the series' id
    def occurrence_of(event, starts_at, ends_at, **changes)
      occurrence = event.dup
      occurrence.id = event.id
      occurrence.assign_attributes(starts_at: starts_at, ends_at: ends_at, **changes)
      occurrence.readonly!
      occurrence.define_singleton_method(:occurrence?) { true }
      occurrence.define_singleton_method(:master_event_id) { event.id }
      occurrence
    end

    def group_events_by_day(events, week_start, week_end)
      days = {}

      (week_start..week_end).each do |date|
        days[date] = []
      end

      events.each do |event|
        event_start_date = event.starts_at.to_date
        event_end_date = event.ends_at.to_date

        # Handle multi-day events
        (event_start_date..event_end_date).each do |date|
          next unless days.key?(date)
          days[date] << event
        end
      end

      # Sort events within each day by start time
      days.transform_values do |day_events|
        day_events.uniq { |e| [ e.id, e.starts_at ] }.sort_by do |event|
          [ event.all_day? ? 0 : 1, event.starts_at ]
        end
      end
    end
  end
end

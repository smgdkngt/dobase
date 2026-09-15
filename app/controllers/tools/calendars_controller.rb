# frozen_string_literal: true

module Tools
  class CalendarsController < ApplicationController
    include ToolAuthorization

    # The longest date range the JSON API returns; any three calendar months fit.
    MAX_RANGE_DAYS = 92

    class InvalidDateRange < StandardError; end

    allow_access_tokens

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
    before_action :require_calendar_account

    def show
      @calendar_account = @tool.calendar_account
      @calendars = @calendar_account.calendars.enabled.by_position

      respond_to do |format|
        format.html { load_week }
        format.turbo_stream { load_week }
        format.json { load_date_range }
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

    def require_calendar_account
      return if @tool.calendar_account

      if request.format.json?
        render json: { error: "Calendar account not configured" }, status: :not_found
      elsif @tool.owned_by?(current_user)
        redirect_to new_tool_calendar_account_path(@tool)
      else
        redirect_to tool_path(@tool), alert: "Calendar account not configured."
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
      range_start = start_date.beginning_of_day
      range_end = end_date.end_of_day

      base_events = @calendar_account.events
        .joins(:calendar)
        .where(calendar_calendars: { enabled: true })
        .by_start

      events = []

      # Non-recurring events in range
      non_recurring = base_events
        .non_recurring
        .in_range(range_start, range_end)
        .includes(:calendar)

      events.concat(non_recurring.to_a)

      # Recurring events - expand occurrences
      recurring = base_events.recurring.includes(:calendar)

      recurring.find_each do |event|
        occurrences = expand_recurrence(event, range_start, range_end)
        events.concat(occurrences)
      end

      events.sort_by(&:starts_at)
    end

    def expand_recurrence(event, range_start, range_end)
      return [] unless event.recurrence_schedule.present?

      schedule = IceCube::Schedule.from_yaml(event.recurrence_schedule)
      duration = event.ends_at - event.starts_at

      occurrences = schedule.occurrences_between(range_start, range_end)

      occurrences.map do |occurrence_start|
        # Create a virtual event object for this occurrence
        occurrence_event = event.dup
        occurrence_event.id = event.id
        occurrence_event.starts_at = occurrence_start
        occurrence_event.ends_at = occurrence_start + duration
        occurrence_event.readonly!
        occurrence_event.define_singleton_method(:occurrence?) { true }
        occurrence_event.define_singleton_method(:master_event_id) { event.id }
        occurrence_event
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to expand recurrence for event #{event.id}: #{e.message}")
      []
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

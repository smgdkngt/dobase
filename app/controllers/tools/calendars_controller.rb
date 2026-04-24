# frozen_string_literal: true

module Tools
  class CalendarsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
    before_action :require_calendar_setup

    def show
      @calendar_account = @tool.calendar_account
      @calendars = @tool.calendars.enabled.by_position

      # Calculate week range
      @week_start = parse_week_start(params[:week_start])
      @week_end = @week_start + 6.days

      # Fetch events for the week
      @events = fetch_events_for_range(@week_start, @week_end)

      # Group events by day
      @events_by_day = group_events_by_day(@events, @week_start, @week_end)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

    def require_calendar_setup
      return if @tool.calendar_account || @tool.calendars.any?

      if @tool.owned_by?(current_user)
        redirect_to new_tool_calendar_account_path(@tool)
      else
        redirect_to tool_path(@tool), alert: "Calendar account not configured."
      end
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

      base_events = Calendars::Event
        .joins(:calendar)
        .where(calendar_calendars: { tool_id: @tool.id, enabled: true })
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

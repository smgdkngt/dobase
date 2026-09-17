# frozen_string_literal: true

module CalendarsHelper
  def navigate_date(date, direction)
    case direction.to_sym
    when :prev
      date - 1.week
    when :next
      date + 1.week
    else
      date
    end
  end

  # The shortest an event is drawn in the week grid, in minutes (an hour is 60px)
  MIN_EVENT_MINUTES = 20

  # The timed events of a day with their column, side by side where they overlap, like
  # [[event, column, columns], ...]. Events that overlap each other, directly or through
  # another event, share the width of the day between them.
  def day_columns(events, day)
    day_start, day_end = day.beginning_of_day, day.end_of_day
    spans = events.map do |event|
      starts = [ event.starts_at, day_start ].max
      ends = [ event.ends_at, day_end ].min
      # Short events take the room they're drawn in
      [ event, starts, [ ends, starts + MIN_EVENT_MINUTES.minutes ].max ]
    end

    groups = []
    spans.sort_by { |_, starts, ends| [ starts, -ends.to_f ] }.each do |event, starts, ends|
      groups << { ends: ends, columns: [], events: [] } if groups.empty? || starts >= groups.last[:ends]
      group = groups.last
      group[:ends] = [ group[:ends], ends ].max

      # The first column that's free again, where each column remembers when its last event ends
      column = group[:columns].index { |column_ends| column_ends <= starts } || group[:columns].size
      group[:columns][column] = ends
      group[:events] << [ event, column ]
    end

    groups.flat_map { |group| group[:events].map { |event, column| [ event, column, group[:columns].size ] } }
  end

  def format_week_header(week_start, week_end)
    if week_start.year == week_end.year
      if week_start.month == week_end.month
        # Same month: "Feb 10 - 16, 2026"
        "#{week_start.strftime('%b %d')} - #{week_end.strftime('%d')}, #{week_end.year}"
      else
        # Different months, same year: "Jan 28 - Feb 3, 2026"
        "#{week_start.strftime('%b %d')} - #{week_end.strftime('%b %d')}, #{week_end.year}"
      end
    else
      # Different years: "Dec 29, 2025 - Jan 4, 2026"
      "#{week_start.strftime('%b %d, %Y')} - #{week_end.strftime('%b %d, %Y')}"
    end
  end

  def format_event_time(event)
    return "All day" if event.all_day?

    if event.starts_at.to_date == event.ends_at.to_date
      "#{event.starts_at.strftime('%l:%M %p').strip} - #{event.ends_at.strftime('%l:%M %p').strip}"
    else
      "#{event.starts_at.strftime('%b %d, %l:%M %p').strip} - #{event.ends_at.strftime('%b %d, %l:%M %p').strip}"
    end
  end

  # Calendars a mail invite can be added to: enabled, writable, and in a calendar tool the user can access
  def invite_target_calendars
    @invite_target_calendars ||= Calendars::Calendar.enabled.writable
      .joins(:account).where(calendar_accounts: { tool_id: current_user.accessible_tools.select(:id) })
      .includes(account: :tool).order(:calendar_account_id, :position).to_a
  end

  def event_color_classes(event)
    color = event.calendar.color_hex
    # Return inline style for custom colors
    { style: "background-color: #{color}; border-left-color: #{color};" }
  end

  def day_header_classes(date)
    classes = []
    classes << "text-blue-600" if date == Date.current
    classes << "text-gray-400" if date < Date.current
    classes.join(" ")
  end
end

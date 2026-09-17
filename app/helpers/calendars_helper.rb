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

  # The calendar fetches event details into its dialog, and loads the form into the dialog's frame
  def in_event_dialog?
    request.xhr? || turbo_frame_request?
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

  # "Sep 16, 12:00 PM – 1:30 PM", "Sep 16, 10:00 PM – Sep 17, 1:00 AM", or for all-day
  # events their days, which are dates and don't shift with the zone: "Sep 16 – Sep 18"
  def format_event_time(event)
    if event.all_day?
      return format_date(event.first_day) if event.last_day <= event.first_day

      "#{format_date(event.first_day)} – #{format_date(event.last_day)}"
    elsif event.starts_at.to_date == event.ends_at.to_date
      "#{format_datetime(event.starts_at)} – #{format_time(event.ends_at)}"
    else
      "#{format_datetime(event.starts_at)} – #{format_datetime(event.ends_at)}"
    end
  end

  # The week grid's hour labels, kept short: "12 AM", "9 AM", "1 PM"
  def format_hour(hour)
    Time.zone.today.in_time_zone.change(hour: hour).strftime("%-l %p")
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

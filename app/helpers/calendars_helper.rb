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

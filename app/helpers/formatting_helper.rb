# frozen_string_literal: true

# Shared formats for sizes, dates and times, so every screen reads the same.
# Times are shown in the viewer's zone (`Time.zone`, set from their timezone).
#
#   human_file_size(8_700)       # => "8.5 KB"
#   format_time(time)            # => "6:05 PM"
#   format_date(date)            # => "Sep 16" (this year) / "Sep 16, 2025"
#   format_datetime(time)        # => "Sep 16, 6:05 PM" / "Sep 16, 2025, 6:05 PM"
#   local_time_tag(time)         # => <time> with "6:05 PM", redrawn in the viewer's zone
module FormattingHelper
  def human_file_size(bytes)
    HumanFileSize.format(bytes)
  end

  def format_time(time)
    return if time.nil?

    time.in_time_zone.strftime("%-I:%M %p")
  end

  def format_date(date)
    return if date.nil?

    date = date.in_time_zone.to_date if date.respond_to?(:in_time_zone) && !date.is_a?(Date)
    date.year == Time.zone.today.year ? date.strftime("%b %-d") : date.strftime("%b %-d, %Y")
  end

  def format_datetime(time)
    return if time.nil?

    "#{format_date(time.in_time_zone)}, #{format_time(time)}"
  end

  # A time in HTML that other people may see too, like a chat message broadcast from the
  # sender's request: the browser redraws it in the viewer's zone. Without the period,
  # it reads "6:05".
  def local_time_tag(time, period: true, **options)
    return if time.nil?

    text = period ? format_time(time) : time.in_time_zone.strftime("%-I:%M")
    tag.time(text, datetime: time.utc.iso8601, **options.except(:data),
      data: { controller: "local-time", local_time_period_value: period, **options.fetch(:data, {}) })
  end
end

# frozen_string_literal: true

# Shared formats for sizes, dates and times, so every screen reads the same.
# Times are shown in the viewer's zone (`Time.zone`, set from their timezone).
#
#   human_file_size(8_700)       # => "8.5 KB"
#   format_time(time)            # => "6:05 PM"
#   format_date(date)            # => "Sep 16" (this year) / "Sep 16, 2025"
#   format_datetime(time)        # => "Sep 16, 6:05 PM" / "Sep 16, 2025, 6:05 PM"
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
end

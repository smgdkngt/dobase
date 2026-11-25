# frozen_string_literal: true

# Shared formats for sizes, dates and times, so every screen reads the same.
# Times are shown in the viewer's zone (`Time.zone`, set from their timezone), and in
# the page's language: by its formats (`date.formats` and `time.formats` in its locale
# file), in its calendar and with its digits (Translation.localize). In Persian that is
# the solar (Jalali) calendar, Persian digits and the 24-hour clock.
#
#   human_file_size(8_700)       # => "8.5 KB"
#   format_time(time)            # => "6:05 PM"                       "۱۸:۰۵"
#   format_date(date)            # => "Sep 16" (this year) / "Sep 16, 2025"   "۲۵ شهریور" / "۲۵ شهریور ۱۴۰۴"
#   format_datetime(time)        # => "Sep 16, 6:05 PM" / "Sep 16, 2025, 6:05 PM"
#   format_weekday(date)         # => "Tuesday" ("Tue" with short: true)
#   format_month(date)           # => "September 2025"
#   format_day_number(date)      # => "16"
#   format_long_date(date)       # => "Tuesday, September 16, 2025"
#   ago(time)                    # => "5 minutes ago"
#   mail_list_date(time)         # => "6:05 PM" (today) / "Sep 16" / "Sep 16, 2025"
#   local_time_tag(time)         # => <time> with "6:05 PM", redrawn in the viewer's zone
#   posted_at_tag(time)          # => <time> "5 minutes ago" (today) / "Sep 16, 6:05 PM"
module FormattingHelper
  include Translation::Methods

  def human_file_size(bytes)
    Translation.digits(HumanFileSize.format(bytes))
  end

  def format_time(time)
    return if time.nil?

    Translation.localize(time.in_time_zone, :clock)
  end

  # year: true says the year this year too, where the date stands alone (a title)
  def format_date(date, year: false)
    return if date.nil?

    date = date.in_time_zone.to_date if date.respond_to?(:in_time_zone) && !date.is_a?(Date)
    with_year = year || Translation.date_parts(date).first != Translation.date_parts(Time.zone.today).first
    Translation.localize(date, with_year ? :day_and_year : :day)
  end

  def format_datetime(time, year: false)
    return if time.nil?

    _("%{date}, %{time}", date: format_date(time.in_time_zone, year: year), time: format_time(time))
  end

  def format_weekday(date, short: false)
    return if date.nil?

    Translation.localize(date, short ? :weekday_short : :weekday)
  end

  # The month a date is in, with its year: a calendar's title
  def format_month(date)
    return if date.nil?

    Translation.localize(date, :month_and_year)
  end

  # The day of the month, as a calendar's day shows it
  def format_day_number(date)
    Translation.localize(date, :day_of_month)
  end

  # The month or months a week of the calendar lies in: "September 2025",
  # "Sep – Oct 2025", "Dec 2025 – Jan 2026"; by the months of the language's calendar
  def calendar_week_title(week_start, week_end)
    first, last = Translation.date_parts(week_start), Translation.date_parts(week_end)
    if first[0..1] == last[0..1]
      format_month(week_start)
    elsif first[0] == last[0]
      "#{Translation.localize(week_start, :week_start)} – #{Translation.localize(week_end, :week_end)}"
    else
      "#{Translation.localize(week_start, :week_start_with_year)} – #{Translation.localize(week_end, :week_end)}"
    end
  end

  # A day in full, weekday and all
  def format_long_date(date)
    return if date.nil?

    date = date.in_time_zone.to_date if date.respond_to?(:in_time_zone) && !date.is_a?(Date)
    Translation.localize(date, :long_day)
  end

  # How long ago, as a phrase: "5 minutes ago"
  def ago(time)
    return if time.nil?

    _("%{time} ago", time: Translation.digits(time_ago_in_words(time)))
  end

  # When mail came, as a list of it says it: today's by its time, older by its day
  def mail_list_date(time)
    return if time.nil?

    time.in_time_zone.to_date == Time.zone.today ? format_time(time) : format_date(time)
  end

  # A time in HTML that other people may see too, like a chat message broadcast from the
  # sender's request: the browser redraws it in the viewer's zone and language. Without
  # the period, it reads "6:05". With the day, a time more than a day ago says which
  # ("Yesterday, 6:05 PM", "Sep 16, 6:05 PM").
  def local_time_tag(time, period: true, day: false, **options)
    return if time.nil?

    text = period ? format_time(time) : Translation.localize(time.in_time_zone, :clock_without_period)
    text = with_day(time, text) if day
    tag.time(text, datetime: time.utc.iso8601, **options.except(:data),
      data: { controller: "local-time", local_time_period_value: period, local_time_day_value: (day if day), **options.fetch(:data, {}) }.compact)
  end

  # When a comment was written: today's as how long ago, older ones by their day and time,
  # which a relative "about 1 month ago" never said. The full moment is in the title.
  def posted_at_tag(time, **options)
    return if time.nil?

    text = time.in_time_zone.to_date == Time.zone.today ? ago(time) : format_datetime(time)
    tag.time(text, datetime: time.utc.iso8601, title: format_datetime(time, year: true), **options)
  end

  private

  # As local_time_controller.js writes it
  def with_day(time, text)
    elapsed = Time.current - time
    if elapsed < 24.hours
      text
    elsif elapsed < 48.hours
      _("Yesterday, %{time}", time: text)
    else
      _("%{date}, %{time}", date: format_date(time), time: text)
    end
  end
end

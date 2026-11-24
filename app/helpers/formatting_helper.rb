# frozen_string_literal: true

# Shared formats for sizes, dates and times, so every screen reads the same.
# Times are shown in the viewer's zone (`Time.zone`, set from their timezone), and in
# the page's language: in Persian by the solar (Jalali) calendar, with Persian digits
# and the 24-hour clock (Translation::Jalali).
#
#   human_file_size(8_700)       # => "8.5 KB"
#   format_time(time)            # => "6:05 PM"                       "۱۸:۰۵"
#   format_date(date)            # => "Sep 16" (this year) / "Sep 16, 2025"   "۲۵ شهریور" / "۲۵ شهریور ۱۴۰۴"
#   format_datetime(time)        # => "Sep 16, 6:05 PM" / "Sep 16, 2025, 6:05 PM"
#   format_weekday(date)         # => "Tuesday" ("Tue" with short: true)
#   format_month(date)           # => "September 2025"
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

    time = time.in_time_zone
    persian? ? Translation.digits(time.strftime("%H:%M")) : time.strftime("%-I:%M %p")
  end

  # year: true says the year this year too, where the date stands alone (a title)
  def format_date(date, year: false)
    return if date.nil?

    date = date.in_time_zone.to_date if date.respond_to?(:in_time_zone) && !date.is_a?(Date)
    with_year = year || date.year != Time.zone.today.year
    if persian?
      jalali_year, _month, day = Translation::Jalali.from(date)
      this_year = Translation::Jalali.from(Time.zone.today).first
      text = "#{day} #{Translation::Jalali.month_name(date)}"
      text += " #{jalali_year}" if year || jalali_year != this_year
      Translation.digits(text)
    else
      with_year ? date.strftime("%b %-d, %Y") : date.strftime("%b %-d")
    end
  end

  def format_datetime(time, year: false)
    return if time.nil?

    "#{format_date(time.in_time_zone, year: year)}#{persian? ? '،' : ','} #{format_time(time)}"
  end

  def format_weekday(date, short: false)
    return if date.nil?

    persian? ? Translation::Jalali.weekday(date, short: short) : date.strftime(short ? "%a" : "%A")
  end

  # The month a date is in, with its year: a calendar's title
  def format_month(date)
    return if date.nil?

    if persian?
      Translation.digits("#{Translation::Jalali.month_name(date)} #{Translation::Jalali.from(date).first}")
    else
      date.strftime("%B %Y")
    end
  end

  # The month or months a week of the calendar lies in: "September 2025",
  # "Sep – Oct 2025", "Dec 2025 – Jan 2026"; in Persian by the Jalali months
  def calendar_week_title(week_start, week_end)
    if persian?
      first, last = Translation::Jalali.from(week_start), Translation::Jalali.from(week_end)
      return format_month(week_start) if first[0..1] == last[0..1]

      start_name, end_name = Translation::Jalali.month_name(week_start), Translation::Jalali.month_name(week_end)
      text = first[0] == last[0] ? "#{start_name} – #{end_name} #{last[0]}" : "#{start_name} #{first[0]} – #{end_name} #{last[0]}"
      Translation.digits(text)
    elsif week_start.month == week_end.month
      week_start.strftime("%B %Y")
    elsif week_start.year == week_end.year
      "#{week_start.strftime("%b")} – #{week_end.strftime("%b %Y")}"
    else
      "#{week_start.strftime("%b %Y")} – #{week_end.strftime("%b %Y")}"
    end
  end

  # Whether dates are written by the Jalali calendar
  def persian_date? = persian?

  # A day in full, weekday and all
  def format_long_date(date)
    return if date.nil?

    date = date.in_time_zone.to_date if date.respond_to?(:in_time_zone) && !date.is_a?(Date)
    persian? ? "#{format_weekday(date)}، #{format_date(date, year: true)}" : date.strftime("%A, %B %-d, %Y")
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
  # sender's request: the browser redraws it in the viewer's zone. Without the period,
  # it reads "6:05".
  def local_time_tag(time, period: true, **options)
    return if time.nil?

    text = period || persian? ? format_time(time) : time.in_time_zone.strftime("%-I:%M")
    tag.time(text, datetime: time.utc.iso8601, **options.except(:data),
      data: { controller: "local-time", local_time_period_value: period, **options.fetch(:data, {}) })
  end

  # When a comment was written: today's as how long ago, older ones by their day and time,
  # which a relative "about 1 month ago" never said. The full moment is in the title.
  def posted_at_tag(time, **options)
    return if time.nil?

    text = time.in_time_zone.to_date == Time.zone.today ? ago(time) : format_datetime(time)
    tag.time(text, datetime: time.utc.iso8601, title: format_datetime(time, year: true), **options)
  end

  private

  def persian? = I18n.locale.to_s == "fa"
end

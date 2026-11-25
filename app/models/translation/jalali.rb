# frozen_string_literal: true

#   Translation::Jalali.from(Date.new(2025, 3, 21))  # => [1404, 1, 1]
module Translation::Jalali
  DAYS_BEFORE_MONTH = [ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 ].freeze

  module_function

  def from(date)
    gy, gm, gd = date.year, date.month, date.day
    gy2 = gm > 2 ? gy + 1 : gy
    days = 355_666 + (365 * gy) + ((gy2 + 3) / 4) - ((gy2 + 99) / 100) + ((gy2 + 399) / 400) + gd + DAYS_BEFORE_MONTH[gm - 1]
    year = -1595 + (33 * (days / 12_053))
    days %= 12_053
    year += 4 * (days / 1461)
    days %= 1461
    if days > 365
      year += (days - 1) / 365
      days = (days - 1) % 365
    end
    if days < 186
      [ year, 1 + (days / 31), 1 + (days % 31) ]
    else
      [ year, 7 + ((days - 186) / 30), 1 + ((days - 186) % 30) ]
    end
  end
end

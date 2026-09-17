# frozen_string_literal: true

require "test_helper"

class FormattingHelperTest < ActionView::TestCase
  test "human_file_size uses one unit style for every size" do
    assert_equal "0 B", human_file_size(0)
    assert_equal "0 B", human_file_size(nil)
    assert_equal "397 B", human_file_size(397)
    assert_equal "1 KB", human_file_size(1024)
    assert_equal "8.5 KB", human_file_size(8_700)
    assert_equal "25 MB", human_file_size(25.megabytes)
    assert_equal "1.5 GB", human_file_size(1.5.gigabytes)
  end

  test "records with a file_size share the format" do
    assert_equal "397 B", Files::Item.new(file_size: 397).human_file_size
    assert_equal "0 B", Files::Item.new(file_size: nil).human_file_size
  end

  test "format_time shows a 12-hour clock without a leading zero in the viewer's zone" do
    Time.use_zone("Europe/Amsterdam") do
      assert_equal "7:05 AM", format_time(Time.utc(2026, 9, 16, 5, 5))
      assert_equal "1:00 PM", format_time(Time.utc(2026, 9, 16, 11, 0))
    end
    assert_nil format_time(nil)
  end

  test "format_date leaves out the current year" do
    travel_to Time.zone.local(2026, 9, 17, 12) do
      assert_equal "Sep 6", format_date(Date.new(2026, 9, 6))
      assert_equal "Dec 24, 2025", format_date(Date.new(2025, 12, 24))
    end
    assert_nil format_date(nil)
  end

  test "format_datetime combines date and time in the viewer's zone" do
    travel_to Time.utc(2026, 9, 17, 12) do
      Time.use_zone("America/New_York") do
        assert_equal "Sep 15, 11:30 PM", format_datetime(Time.utc(2026, 9, 16, 3, 30))
        assert_equal "Jan 2, 2025, 9:00 AM", format_datetime(Time.utc(2025, 1, 2, 14, 0))
      end
    end
    assert_nil format_datetime(nil)
  end
  test "local_time_tag writes the time for the browser to redraw in the viewer's zone" do
    Time.use_zone("America/New_York") do
      tag = Nokogiri::HTML5.fragment(local_time_tag(Time.utc(2026, 9, 16, 3, 30))).at("time")

      assert_equal "11:30 PM", tag.text
      assert_equal "2026-09-16T03:30:00Z", tag["datetime"]
      assert_equal "local-time", tag["data-controller"]

      assert_equal "11:30", Nokogiri::HTML5.fragment(local_time_tag(Time.utc(2026, 9, 16, 3, 30), period: false)).at("time").text
    end
    assert_nil local_time_tag(nil)
  end
end

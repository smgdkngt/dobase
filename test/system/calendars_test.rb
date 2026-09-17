# frozen_string_literal: true

require "application_system_test_case"

class CalendarsTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_calendar)
    sign_in_as users(:one)
  end

  test "next and previous week move a week at a time west of UTC" do
    in_browser_time_zone("America/New_York") do
      visit tool_calendar_path(@tool, week_start: "2030-01-07")
      wait_for_stimulus "calendar"
      find("button[title^='Next week']").click
      assert_current_path tool_calendar_path(@tool, week_start: "2030-01-14")

      wait_for_stimulus "calendar"
      find("button[title^='Previous week']").click
      assert_current_path tool_calendar_path(@tool, week_start: "2030-01-07")
    end
  end

  test "a failed save shows its errors in the event dialog, and Cancel closes it" do
    event = calendars_calendars(:personal).events.create!(uid: "dentist@dobase", summary: "Dentist",
      starts_at: Time.utc(2030, 1, 8, 14), ends_at: Time.utc(2030, 1, 8, 15))
    visit tool_calendar_path(@tool, week_start: "2030-01-07")
    wait_for_turbo
    wait_for_stimulus "calendar"

    find("[data-event-id='#{event.id}']").click
    within("dialog#event-details-modal[open]") do
      click_on "Edit"
      find_field("calendars_event[end_time]").set(Time.utc(2030, 1, 8, 13))
      click_on "Save Changes"
      assert_text "End must be after the start"
      click_on "Cancel"
    end

    assert_no_selector "dialog#event-details-modal[open]"
    assert_selector "[data-event-id='#{event.id}']", text: "Dentist"
    assert_equal Time.utc(2030, 1, 8, 15), event.reload.ends_at
  end

  test "the repeat options of a new event follow the slot picked in the grid" do
    visit tool_calendar_path(@tool, week_start: "2030-01-07")
    wait_for_turbo
    wait_for_stimulus "calendar"

    find(".week-column[data-date='2030-01-11'] .hour-slot[data-hour='10']").click
    within("dialog#new-event-modal[open]") do
      select "Weekly", from: "calendars_event[recurrence_frequency]"
      assert_equal [ "FR" ], all("input[name='calendars_event[recurrence_days_of_week][]']", visible: :all).select(&:checked?).map(&:value)
      assert_selector "[data-recurrence-form-target=weekdayLabel]", text: "The 2nd Friday", visible: :all
      assert_checked_field "Never"
    end
  end

  private

  def in_browser_time_zone(zone)
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: zone)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "")
  end
end

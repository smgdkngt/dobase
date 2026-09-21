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

  test "a week opens at the start of the day, just under the day names" do
    visit tool_calendar_path(@tool, week_start: "2030-01-07")
    wait_for_stimulus "calendar"

    # 8 AM sits right below the sticky header, not hidden under it (or as far
    # down as a tall window lets it go)
    opened_at = <<~JS
      (() => {
        const grid = document.querySelector("[data-calendar-target='grid']")
        const header = grid.querySelector(".week-head").getBoundingClientRect()
        const slot = grid.querySelector("[data-hour='8']").getBoundingClientRect()
        const scrolledToEnd = grid.scrollTop >= grid.scrollHeight - grid.clientHeight - 1
        return Math.round(slot.top - header.bottom) === 0 || (scrolledToEnd && slot.top > header.bottom)
      })()
    JS
    assert page.document.synchronize { evaluate_script(opened_at) || raise(Capybara::ExpectationNotMet) }
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

    click_hour_slot("2030-01-11", 10)
    within("dialog#new-event-modal[open]") do
      select "Weekly", from: "calendars_event[recurrence_frequency]"
      assert_equal [ "FR" ], all("input[name='calendars_event[recurrence_days_of_week][]']", visible: :all).select(&:checked?).map(&:value)
      assert_selector "[data-recurrence-form-target=weekdayLabel]", text: "The 2nd Friday", visible: :all
      assert_checked_field "Never"
    end
  end

  private

  # The grid scrolls itself to the current hour when it connects, in a frame of
  # its own. A click sent before that lands on whatever slid under the cursor,
  # which is why this test came and went on CI.
  def click_hour_slot(date, hour)
    selector = ".week-column[data-date='#{date}'] .hour-slot[data-hour='#{hour}']"
    find(selector).execute_script("this.scrollIntoView({ block: 'center' })")
    find(selector).click
    return if has_selector?("dialog#new-event-modal[open]", wait: 3)

    find(selector).click
  end

  def in_browser_time_zone(zone)
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: zone)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "")
  end
end

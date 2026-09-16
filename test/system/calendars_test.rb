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

  private

  def in_browser_time_zone(zone)
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: zone)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "")
  end

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end

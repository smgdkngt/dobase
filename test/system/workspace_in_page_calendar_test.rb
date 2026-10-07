# frozen_string_literal: true

require "application_system_test_case"

# A calendar as a tile in the workspace's own page (workspace_controller.js#inThisPage).
# What every such tile does is in workspace_in_page_test.rb; this is what a calendar
# has of its own: weeks gone through inside the tile, and events in dialogs over it.
class WorkspaceInPageCalendarTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  CALENDAR = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @tool = tools(:my_calendar)
    @event = calendars_calendars(:personal).events.create!(uid: "dentist@dobase", summary: "Dentist",
      starts_at: Time.utc(2030, 1, 8, 14), ends_at: Time.utc(2030, 1, 8, 15))
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path("in-page": "todos,boards,chat,docs,calendar", open: tool_calendar_path(@tool, week_start: "2030-01-07"))
    wait_for_stimulus "workspace"
    assert_selector "#{CALENDAR} [data-event-id='#{@event.id}']", text: "Dentist"
    wait_for_stimulus "calendar"
    within(".workspace-hint") { click_on "Got it" }
  end

  teardown do
    page.execute_script("try { localStorage.removeItem('dobase:workspace:in-page') } catch (error) {}")
  end

  test "the weeks are gone through in the tile, by button and by key" do
    within(CALENDAR) { find("button[title^='Next week']").click }
    assert_selector "#{CALENDAR}[src*='week_start=2030-01-14']"
    assert_no_selector "#{CALENDAR} [data-event-id='#{@event.id}']"

    wait_for_stimulus "calendar"
    into_the_calendar.send_keys([ mod, :arrow_left ])
    assert_selector "#{CALENDAR}[src*='week_start=2030-01-07']"
    assert_selector "#{CALENDAR} [data-event-id='#{@event.id}']"
    assert_current_path workspace_path
    assert_equal 0, page.evaluate_script("window.frames.length")
  end

  test "an event's details open over the window, and it is changed from there" do
    within(CALENDAR) { find("[data-event-id='#{@event.id}']").click }

    assert_no_selector ".workspace-float iframe"
    within("dialog#event-details-modal[open]") do
      assert_text "Dentist"
      click_on "Edit"
      fill_in "calendars_event[summary]", with: "Dentist, moved"
      click_on "Save Changes"
    end

    assert_selector "#{CALENDAR} [data-event-id='#{@event.id}']", text: "Dentist, moved"
    assert_no_selector "dialog#event-details-modal[open]"
    assert_equal "Dentist, moved", @event.reload.summary
    assert_current_path workspace_path
  end

  test "an event is made with the key for it, and shows in the tile" do
    into_the_calendar.send_keys("n")

    within("dialog#new-event-modal[open]") do
      fill_in "calendars_event[summary]", with: "Lunch"
      find_field("calendars_event[start_time]").set(Time.utc(2030, 1, 9, 12))
      find_field("calendars_event[end_time]").set(Time.utc(2030, 1, 9, 13))
      click_on "Create"
    end

    assert_selector "#{CALENDAR} [data-event-id]", text: "Lunch"
    assert_selector "#flash", text: "Event created successfully."
    assert_current_path workspace_path
    assert_selector CALENDAR, count: 1
  end

  test "a click on an hour starts an event at that hour" do
    slot = "#{CALENDAR} .week-column[data-date='2030-01-10'] .hour-slot[data-hour='10']"
    find(slot).execute_script("this.scrollIntoView({ block: 'center' })")
    find(slot).click

    within("dialog#new-event-modal[open]") do
      assert_match(/\A2030-01-10T10:[03]0/, find_field("calendars_event[start_time]").value)
    end
  end

  test "a link to an event opens it in the tile that is there" do
    page.execute_script("Turbo.visit(arguments[0])", tool_calendar_path(@tool, event: @event.id, week_start: "2030-01-07"))

    assert_selector "dialog#event-details-modal[open]", text: "Dentist"
    assert_selector CALENDAR, count: 1
    assert_current_path workspace_path
  end

  test "the calendar opens at the hour it asks for, as it does in a frame of its own" do
    # How far the hour it asks for is from the top of the hours, against how far it scrolled
    off = page.document.synchronize do
      measured = page.evaluate_script(<<~JS)
        (() => {
          const grid = document.querySelector(#{"#{CALENDAR} [data-calendar-target='grid']".to_json})
          const body = grid.querySelector("[data-scroll-hour]")
          const slot = body.querySelector(`[data-hour="${body.dataset.scrollHour}"]`)
          // (where things are on the screen is measured as drawn, the scrolling as laid out)
          const down = (slot.getBoundingClientRect().top - body.getBoundingClientRect().top) / (grid.currentCSSZoom || 1)
          // (late in the day the grid can't scroll as far as that hour)
          const furthest = grid.scrollHeight - grid.clientHeight
          return grid.scrollTop > 0 ? Math.abs(Math.min(down, furthest) - grid.scrollTop) : null
        })()
      JS
      measured.nil? ? raise(Capybara::ExpectationNotMet, "The calendar hasn't scrolled yet") : measured
    end
    assert_operator off, :<, 3, "The calendar is scrolled #{off}px away from the hour it opens at"
  end

  private

  # The keyboard in the calendar, without a click (which would start an event)
  def into_the_calendar
    find("#{CALENDAR} .tile-page").tap { |tile| tile.execute_script("this.focus()") }
  end

  def mod = page.evaluate_script("navigator.platform").match?(/Mac|iP/) ? :meta : :control
end

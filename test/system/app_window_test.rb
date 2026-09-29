# frozen_string_literal: true

require "application_system_test_case"

# Headless Chrome can't be an installed app, and CDP can't emulate display-mode, so
# these tests mark the window the way application.js remembers it: in sessionStorage.
class AppWindowTest < ApplicationSystemTestCase
  setup do
    sign_in_as(users(:one))
  end

  test "in a browser tab the interface keeps behaving like a web page" do
    visit tool_board_path(tools(:project_board))
    wait_for_turbo

    assert_no_selector "html[data-app-window]", visible: :all
    assert_equal "pointer", style_of(".sidebar-tool-link", "cursor")
    assert_equal "auto", style_of(".tool-topbar-title", "user-select")
  end

  test "an installed app window gets the arrow cursor and an unselectable interface" do
    open_as_installed_app
    visit tool_board_path(tools(:project_board))
    wait_for_turbo

    assert_selector "html[data-app-window]", visible: :all
    assert_equal "default", style_of(".sidebar-tool-link", "cursor")
    assert_equal "none", style_of(".tool-topbar-title", "user-select")
    assert_equal "none", style_of("body", "overscroll-behavior-y")

    page.execute_script("document.querySelector('.sidebar').append(Object.assign(document.createElement('input'), { id: 'probe' }))")
    assert_equal "text", style_of("#probe", "user-select")
  end

  private

  def open_as_installed_app
    page.execute_script("sessionStorage.setItem('app-window', '1')")
  end

  def style_of(selector, property)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).getPropertyValue(#{property.to_json})")
  end
end

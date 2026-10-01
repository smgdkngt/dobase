# frozen_string_literal: true

require "application_system_test_case"

class ThemesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "picking a theme recolours the app, and stays on while moving around" do
    visit edit_profile_path(tab: "appearance")
    assert_selector "html[data-theme-version='default']"

    find("button.theme-option[name='theme'][value='tokyo-night']").click

    assert_selector "html[data-theme='tokyo-night'][data-theme-mode='dark']"
    assert_selector "button.theme-option-selected[value='tokyo-night']"
    assert_equal "#1a1b26", css_variable("--color-background")
    assert_equal "dark", page.evaluate_script("getComputedStyle(document.documentElement).colorScheme")
    assert_equal Theme.find("tokyo-night").chrome_color, page.evaluate_script("document.querySelector('meta[name=theme-color]').content")

    # Turbo swaps the body and leaves <html> as it is
    visit tool_board_path(tools(:shared_board))
    assert_selector "html[data-theme='tokyo-night']"
    assert_equal "#1a1b26", css_variable("--color-background")
  end

  test "the app's own look takes a theme off again" do
    @user.choose_theme("gruvbox")
    visit edit_profile_path(tab: "appearance")
    assert_selector "html[data-theme='gruvbox']"

    find("button.theme-option[name='theme'][value='']").click

    assert_selector "html[data-theme-version='default']:not([data-theme])"
    assert_equal "", page.evaluate_script("document.documentElement.style.getPropertyValue('--color-background')")
    assert_selector "meta[name='theme-color']", count: 2, visible: :all
  end

  test "a theme picked somewhere else arrives on an open page without a reload" do
    visit tool_board_path(tools(:shared_board))
    wait_for_stimulus "notifications", "[data-controller~='notifications']"
    page.execute_script("window.stillTheSamePage = true")
    sleep 0.5 # the notification channel has to be subscribed before anything is sent on it

    @user.choose_theme("nord")

    assert_selector "html[data-theme='nord'][data-theme-mode='dark']"
    assert_equal "#2e3440", css_variable("--color-background")
    assert page.evaluate_script("window.stillTheSamePage")

    @user.choose_theme(nil)
    assert_selector "html[data-theme-version='default']:not([data-theme])"
  end

  test "monospace sets the whole interface in the monospace font, and Dobase takes it back" do
    visit edit_profile_path(tab: "appearance")
    own = page.evaluate_script("getComputedStyle(document.body).fontFamily")
    assert_no_match(/monospace/, own)

    find("button.theme-option[name='typeface'][value='mono']").click

    assert_selector "html[data-typeface='mono']"
    assert_selector "button.theme-option-selected[name='typeface'][value='mono']"
    assert_match(/monospace/, page.evaluate_script("getComputedStyle(document.body).fontFamily"))

    find("button.theme-option[name='typeface'][value='']").click

    assert_selector "html:not([data-typeface])"
    assert_equal own, page.evaluate_script("getComputedStyle(document.body).fontFamily")
  end

  test "the command palette puts a theme on, right where you are" do
    visit tool_board_path(tools(:shared_board))
    wait_for_stimulus "command-palette", "dialog[data-controller~='command-palette']"

    find("button", text: "Jump to").click
    assert_no_selector "button[data-type='theme']", visible: true
    find("dialog[open] input").send_keys("rosé")
    assert_selector "button[data-type='theme']", text: "Rosé Pine", count: 1
    find("dialog[open] input").send_keys(:enter)

    assert_selector "html[data-theme='rose-pine'][data-theme-mode='light']"
    assert_equal "rose-pine", @user.reload.theme_name
    assert_current_path tool_board_path(tools(:shared_board))
    assert_equal "#faf4ed", page.evaluate_script("JSON.parse(localStorage.getItem('dobase:theme')).background")
  end

  private

  def css_variable(name)
    page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('#{name}').trim()")
  end
end

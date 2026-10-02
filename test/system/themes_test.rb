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

  test "a theme for when the system is light and one for when it is dark" do
    emulate_scheme "light"
    visit edit_profile_path(tab: "appearance")

    click_on "One for light, one for dark"
    assert_selector ".theme-slot.theme-slot-on[data-scheme='light']", text: "Dobase"

    find("button.theme-option[name='theme'][value='catppuccin-latte']").click
    assert_selector "html[data-theme='catppuccin-latte'][data-theme-follows-system]"
    assert_selector ".theme-slot[data-scheme='light']", text: "Catppuccin Latte"

    # The other one is picked without it going on: the system is light
    find(".theme-slot[data-scheme='dark']").click
    find("button.theme-option[name='theme'][value='tokyo-night']").click
    assert_selector ".theme-slot[data-scheme='dark']", text: "Tokyo Night"
    assert_selector "button.theme-option-selected[name='theme'][value='tokyo-night']"
    assert_selector "html[data-theme='catppuccin-latte']"

    # The system goes dark: the page changes over by itself, and the next one is drawn dark
    emulate_scheme "dark"
    assert_selector "html[data-theme='tokyo-night'][data-theme-mode='dark']"
    visit tool_board_path(tools(:shared_board))
    assert_selector "html[data-theme='tokyo-night']"

    emulate_scheme "light"
    assert_selector "html[data-theme='catppuccin-latte']"

    # One theme again: the one that is on stays
    visit edit_profile_path(tab: "appearance")
    click_on "One theme"
    assert_no_selector ".theme-slots"
    assert_selector "button.theme-option-selected[name='theme'][value='catppuccin-latte']"
    emulate_scheme "dark"
    assert_no_selector "html[data-theme-follows-system]"
    assert_selector "html[data-theme='catppuccin-latte']"
  ensure
    emulate_scheme nil
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

  # What the system says about light and dark, as the browser hears it
  def emulate_scheme(scheme)
    features = scheme ? [ { name: "prefers-color-scheme", value: scheme } ] : []
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: features)
  end
end

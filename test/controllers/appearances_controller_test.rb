# frozen_string_literal: true

require "test_helper"

class AppearancesControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "without a theme the page keeps the app's own look" do
    get edit_profile_path

    assert_select "html[data-theme-version=default]:not([style]):not([data-theme])"
    assert_select "body[data-theme-version-value=default]"
    assert_select "meta[name=theme-color]", 2
  end

  test "the profile offers the app's own look and every built-in theme" do
    get edit_profile_path(tab: "appearance")

    assert_select "button.theme-option[name=theme]", Theme.all.size + 1
    assert_select "button.theme-option-selected[value='']"
    assert_select "button.theme-option[value=tokyo-night]", text: /Tokyo Night/
  end

  test "picking a theme puts it on every page" do
    patch appearance_path, params: { theme: "tokyo-night" }
    assert_redirected_to edit_profile_path(tab: "appearance")
    follow_redirect!

    theme = Theme.find("tokyo-night")
    assert_select "html[data-theme=tokyo-night][data-theme-mode=dark][data-theme-version='#{theme.version}']"
    assert_select "html[style*='--color-background: #1a1b26']"
    assert_select "body[data-theme-version-value='#{theme.version}']"
    assert_select "meta[name=theme-color][data-theme-chrome][content='#{theme.chrome_color}']"
    assert_select "button.theme-option-selected[value=tokyo-night]"
  end

  test "picking a theme tells the pages that are open" do
    assert_broadcast_on("notifications:#{@user.id}", type: "theme", theme: Theme.payload(Theme.find("nord"))) do
      patch appearance_path, params: { theme: "nord" }
    end
  end

  test "picking the app's own look takes the theme off" do
    @user.choose_theme("nord")

    assert_broadcast_on("notifications:#{@user.id}", type: "theme", theme: { version: "default" }) do
      patch appearance_path, params: { theme: "" }
    end

    assert_nil @user.reload.theme
    follow_redirect!
    assert_select "html[data-theme-version=default]:not([style])"
  end

  test "an unknown theme changes nothing" do
    @user.choose_theme("nord")

    patch appearance_path, params: { theme: "no-such-theme" }

    assert_redirected_to edit_profile_path(tab: "appearance")
    assert_equal "That theme doesn't exist.", flash[:alert]
    assert_equal "nord", @user.reload.theme_name
  end

  test "a palette of their own shows as theirs" do
    @user.choose_theme("my-desktop", { "background" => "#101010", "foreground" => "#eeeeee", "accent" => "#ff8800" })

    get edit_profile_path(tab: "appearance")

    assert_select "html[data-theme=my-desktop][style*='--color-background: #101010']"
    assert_select "button.theme-option-selected[disabled]", text: /My Desktop\s+Yours/
    assert_select "button.theme-option-selected", 1
  end

  test "signed out, the sign-in page keeps the theme this browser last had" do
    @user.choose_theme("nord")
    get edit_profile_path
    delete session_path

    get new_session_path

    assert_select "html[data-theme=nord][style*='--color-background: #2e3440']"
    assert_select "svg[aria-label=Dobase] rect[style='fill: var(--color-logo)']"
  end

  test "a palette of their own is kept for the sign-in page too" do
    @user.choose_theme("my-desktop", { "background" => "#101010", "foreground" => "#eeeeee", "accent" => "#ff8800" })
    get edit_profile_path
    delete session_path

    get new_session_path

    assert_select "html[data-theme=my-desktop][style*='--color-background: #101010']"
  end

  test "a browser nobody themed, or whose person went back to the app's own look, has none" do
    get edit_profile_path
    delete session_path
    get new_session_path
    assert_select "html[data-theme-version=default]:not([style])"

    sign_in_as @user
    @user.choose_theme("nord")
    get edit_profile_path
    @user.choose_theme(nil)
    get edit_profile_path
    delete session_path

    get new_session_path
    assert_select "html[data-theme-version=default]:not([style])"
  end

  test "the web app manifest takes the theme's colours" do
    get pwa_manifest_path(format: :json)
    assert_equal "#f5f5f7", response.parsed_body["theme_color"]

    @user.choose_theme("nord")
    get edit_profile_path
    get pwa_manifest_path(format: :json)

    assert_equal Theme.find("nord").chrome_color, response.parsed_body["theme_color"]
    assert_equal Theme.find("nord").chrome_color, response.parsed_body["background_color"]
  end

  test "the command palette offers every theme" do
    get edit_profile_path

    assert_select "dialog[data-controller=command-palette] button[data-type=theme]", Theme.all.size + 1
    assert_select "button[data-type=theme][data-theme=tokyo-night][data-when-typed].hidden", text: /Tokyo Night/
  end
end

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

  test "signed out, a page has no theme" do
    @user.choose_theme("nord")
    delete session_path

    get new_session_path

    assert_select "html[data-theme-version=default]:not([style])"
  end
end

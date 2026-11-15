# frozen_string_literal: true

require "application_system_test_case"

class TimeZonesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    assert_equal "UTC", @user.timezone
    use_browser_time_zone("Europe/Amsterdam")
  end

  test "the sign-up form sends the zone the browser is in" do
    invitation = tools(:shared_board).invitations.create!(email: "newcomer@example.com", invited_by: @user)

    visit invitation_acceptance_path(token: invitation.token)

    assert_field "time_zone", type: :hidden, with: "Europe/Amsterdam"
  end

  test "times shown in UTC in a browser that is elsewhere: one click shows them in its zone" do
    sign_in_as(@user)

    within ".time-zone-notice" do
      assert_text "Times are shown in UTC. Use Europe/Amsterdam?"
      click_on "Switch"
    end

    assert_text "Time zone set to Amsterdam."
    assert_no_selector ".time-zone-notice"
    assert_equal "Europe/Amsterdam", page.evaluate_script("document.querySelector('meta[name=time-zone]').content")
    assert_equal "Amsterdam", @user.reload.timezone
  end

  test "waved away, the offer stays away" do
    sign_in_as(@user)
    wait_for_stimulus("time-zone", "body")

    within(".time-zone-notice") { click_on "Keep UTC" }

    assert_no_selector ".time-zone-notice"
    visit edit_profile_path
    assert_selector "h1, h2", text: "Profile"
    assert_no_selector ".time-zone-notice"
    assert_equal "UTC", @user.reload.timezone
  end
end

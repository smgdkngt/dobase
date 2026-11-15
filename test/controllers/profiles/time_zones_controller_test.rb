# frozen_string_literal: true

require "test_helper"

class Profiles::TimeZonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    assert_equal "UTC", @user.timezone
    sign_in_as @user
  end

  test "a page says so when times are shown in UTC and the browser is somewhere else" do
    cookies[:browser_time_zone] = "Europe/Amsterdam"

    get edit_profile_path

    assert_select ".time-zone-notice", text: /Times are shown in UTC\.\s+Use Europe\/Amsterdam\?/
    assert_select ".time-zone-notice form[action='#{profile_time_zone_path}'] input[name=time_zone][value='Amsterdam']"
  end

  test "no word about it where there is nothing to say" do
    get edit_profile_path
    assert_select ".time-zone-notice", { count: 0 }, "the browser never said where it is"

    cookies[:browser_time_zone] = "UTC"
    get edit_profile_path
    assert_select ".time-zone-notice", { count: 0 }, "the browser is in UTC too"

    cookies[:browser_time_zone] = "Mars/Olympus_Mons"
    get edit_profile_path
    assert_select ".time-zone-notice", { count: 0 }, "a zone nobody knows"

    cookies[:browser_time_zone] = "Europe/Amsterdam"
    cookies[:time_zone_dismissed] = "Europe/Amsterdam"
    get edit_profile_path
    assert_select ".time-zone-notice", { count: 0 }, "waved away for this zone"

    cookies[:time_zone_dismissed] = ""
    @user.update!(timezone: "Lisbon")
    get edit_profile_path
    assert_select ".time-zone-notice", { count: 0 }, "a zone was chosen"
  end

  test "waved away in one zone, it asks again in another" do
    cookies[:browser_time_zone] = "America/New_York"
    cookies[:time_zone_dismissed] = "Europe/Amsterdam"

    get edit_profile_path

    assert_select ".time-zone-notice", text: /Use America\/New York\?/
  end

  test "switching shows times in that zone from then on, back where it was asked" do
    patch profile_time_zone_path, params: { time_zone: "Amsterdam" }, headers: { "Referer" => "http://www.example.com/profile/edit" }

    assert_redirected_to "http://www.example.com/profile/edit"
    assert_equal "Amsterdam", @user.reload.timezone
    assert_equal "Time zone set to Amsterdam.", flash[:notice]
  end

  test "a browser's own name for the zone works as well" do
    patch profile_time_zone_path, params: { time_zone: "Europe/Amsterdam" }

    assert_redirected_to root_path
    assert_equal "Amsterdam", @user.reload.timezone
  end

  test "a zone nobody knows changes nothing" do
    patch profile_time_zone_path, params: { time_zone: "Mars/Olympus_Mons" }

    assert_redirected_to root_path
    assert_equal "UTC", @user.reload.timezone
    assert_equal "That time zone isn't one we know.", flash[:alert]
  end

  test "the API says the zone by the app's name and by the one programs know" do
    @user.update!(timezone: "Eastern Time (US & Canada)")

    get profile_path, headers: api_headers(@user, permission: "read")

    assert_equal "Eastern Time (US & Canada)", response.parsed_body["timezone"]
    assert_equal "America/New_York", response.parsed_body["timezone_identifier"]
  end

  test "a token can't change it: it is the account's" do
    patch profile_time_zone_path, params: { time_zone: "Amsterdam" }, headers: api_headers(@user, permission: "write")

    assert_response :forbidden
    assert_equal "UTC", @user.reload.timezone
  end
end

# frozen_string_literal: true

require "test_helper"

class PageLocaleTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "a page nobody is signed in on is in English when the browser asks for nothing we have" do
    get new_session_path, headers: { "Accept-Language" => "de-DE,de;q=0.9" }

    assert_select "html[lang=en][dir=ltr]"
  end

  test "a page nobody is signed in on is in the language the browser asks for" do
    get new_session_path, headers: { "Accept-Language" => "fa-IR,fa;q=0.9,en;q=0.8" }

    assert_select "html[lang=fa][dir=rtl]"
  end

  test "the language this browser last had comes before what it asks for" do
    cookies[:locale] = "fa"
    get new_session_path, headers: { "Accept-Language" => "en-US,en;q=0.9" }

    assert_select "html[lang=fa]"
  end

  test "a language the app doesn't have in the cookie is passed over" do
    cookies[:locale] = "xx"
    get new_session_path, headers: { "Accept-Language" => "fa" }

    assert_select "html[lang=fa]"
  end

  test "the signed-in person's choice comes before the cookie and the browser" do
    @user.update!(locale: "fa")
    sign_in_as @user
    cookies[:locale] = "en"

    get edit_profile_path, headers: { "Accept-Language" => "en" }

    assert_select "html[lang=fa]"
  end

  test "without a choice of their own, a signed-in person gets what the browser asks for" do
    @user.update!(locale: nil)
    sign_in_as @user

    get edit_profile_path, headers: { "Accept-Language" => "fa" }

    assert_select "html[lang=fa]"
  end

  test "an access token's request is in English, whatever its owner chose" do
    @user.update!(locale: "fa")

    post tools_path, params: { tool: { name: "Nope", tool_type: "spreadsheets" } },
      headers: api_headers(@user).merge("Accept-Language" => "fa"), as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Tool type must exist"
  end

  test "a JSON request from the browser is in English too" do
    @user.update!(locale: "fa")
    sign_in_as @user
    cookies[:locale] = "fa"

    post tools_path, params: { tool: { name: "Nope", tool_type: "spreadsheets" } },
      headers: { "Accept-Language" => "fa" }, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Tool type must exist"
  end

  test "the browser remembers the signed-in person's language, for the sign-in page after signing out" do
    @user.update!(locale: "fa")
    sign_in_as @user

    get edit_profile_path

    assert_equal "fa", cookies[:locale]
  end

  test "a person without a choice of their own leaves no language behind" do
    @user.update!(locale: nil)
    sign_in_as @user
    cookies[:locale] = "fa"

    get edit_profile_path

    assert cookies[:locale].blank?
  end

  test "nobody signed in leaves the cookie as it was" do
    cookies[:locale] = "fa"

    get new_session_path

    assert_equal "fa", cookies[:locale]
  end
end

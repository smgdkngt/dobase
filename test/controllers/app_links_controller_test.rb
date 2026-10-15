# frozen_string_literal: true

require "test_helper"

class AppLinksControllerTest < ActionDispatch::IntegrationTest
  IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1"

  setup { sign_in_as(users(:one)) }

  test "hands the page it names to the app" do
    get "/app/tools/107/mails/new?draft_id=12"

    assert_response :success
    assert_select "head script[src*='app_link'][data-link='web+dobase://tools/107/mails/new?draft_id=12'][data-page='/tools/107/mails/new?draft_id=12']"
    assert_select "a[href='web+dobase://tools/107/mails/new?draft_id=12']", text: "Open in the app"
    assert_select "a[href='/tools/107/mails/new?draft_id=12']", text: "Open here instead"
  end

  test "is a page of its own, without the app around it" do
    get "/app/tools/1"

    assert_select "aside", count: 0
    assert_select "script[type=importmap]", count: 0
  end

  test "without a page it is the start page" do
    get "/app"
    assert_select "head script[data-link='web+dobase://'][data-page='/']"
  end

  test "a page that looks like a file is still that page" do
    get "/app/tools/9/files/report.pdf"
    assert_select "head script[data-page='/tools/9/files/report.pdf']"
  end

  test "a phone goes to the page at once: there is no app to hand it to" do
    get "/app/tools/107/mails/new?draft_id=12", headers: { "User-Agent" => IPHONE }
    assert_redirected_to "/tools/107/mails/new?draft_id=12"
  end

  test "never leaves this instance" do
    [ "/app/%5Cevil.example", "/app/%5C%5Cevil.example/x", "/app//evil.example", "/app/https://evil.example" ].each do |address|
      get address, headers: { "User-Agent" => IPHONE }
      location = URI.parse(response.location)
      assert_equal "www.example.com", location.host, "#{address} redirected to #{response.location}"
      assert_not location.path.start_with?("//"), "#{address} redirected to #{response.location}"
    end
  end

  test "signed out it hands the page on too: the app has a sign-in of its own" do
    delete logout_path
    get "/app/tools/1"

    assert_response :success
    assert_select "head script[data-link='web+dobase://tools/1']"
  end
end

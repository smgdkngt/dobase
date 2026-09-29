# frozen_string_literal: true

require "test_helper"

class ProtocolLinksControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "a web+dobase link opens the page it names" do
    get protocol_link_path(url: "web+dobase://tools/107/mails/new?draft_id=12")
    assert_redirected_to "/tools/107/mails/new?draft_id=12"
  end

  test "any number of slashes after the scheme" do
    get protocol_link_path(url: "web+dobase:/tools/1")
    assert_redirected_to "/tools/1"

    get protocol_link_path(url: "web+dobase:///tools/1")
    assert_redirected_to "/tools/1"
  end

  test "never leaves this instance" do
    [ "web+dobase:////evil.example", "web+dobase:/\\evil.example", "https://evil.example", "//evil.example", "" ].each do |link|
      get protocol_link_path(url: link)
      location = URI.parse(response.location)
      assert_equal "www.example.com", location.host, "#{link.inspect} redirected to #{response.location}"
    end
  end

  test "signed out, it asks to sign in first" do
    delete logout_path
    get protocol_link_path(url: "web+dobase://tools/1")
    assert_redirected_to new_session_path
  end
end

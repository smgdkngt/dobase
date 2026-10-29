# frozen_string_literal: true

require "test_helper"

class ClientIpHeaderTest < ActionDispatch::IntegrationTest
  test "a Client-IP header that disagrees with X-Forwarded-For is ignored, not a 500" do
    post session_path, params: { email_address: users(:one).email_address, password: "password" },
      headers: { "Client-IP" => "136.7.27.164", "X-Forwarded-For" => "203.0.113.9" }

    assert_response :redirect
    assert_equal "203.0.113.9", users(:one).sessions.order(:id).last.ip_address
  end
end

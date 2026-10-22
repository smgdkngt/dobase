# frozen_string_literal: true

require "test_helper"

# `dobase login`: the CLI asks for a code, the person confirms it in a browser,
# and the CLI's polling gets its tokens
class OauthDeviceFlowTest < ActionDispatch::IntegrationTest
  GRANT = "urn:ietf:params:oauth:grant-type:device_code"

  setup do
    @user = users(:one)
    @client = Oauth::Client.register(name: "dobase CLI", redirect_uris: [ "http://127.0.0.1/" ])
  end

  test "the CLI gets a code, waits, and is connected once the person says yes" do
    post "/oauth/device_authorization", params: { client_id: @client.uid }
    assert_response :success
    device = response.parsed_body
    assert_match(/\A[A-Z]{4}-[A-Z]{4}\z/, device["user_code"])
    assert_equal "http://www.example.com/oauth/device", device["verification_uri"]
    assert_equal 5, device["interval"]

    poll(device)
    assert_equal "authorization_pending", response.parsed_body["error"]
    poll(device)
    assert_equal "slow_down", response.parsed_body["error"], "asking again within the interval"

    get device["verification_uri_complete"]
    assert_redirected_to new_session_path

    sign_in_as @user
    get "/oauth/device", params: { user_code: device["user_code"].downcase.delete("-") }
    assert_response :success
    assert_includes response.body, "Connect dobase CLI"

    post "/oauth/device", params: { user_code: device["user_code"], decision: "allow", permission: "write", agent: "true" }
    assert_response :success
    assert_includes response.body, "Connected"

    travel 6.seconds do
      poll(device)
    end
    assert_response :success
    tokens = response.parsed_body
    connection = @user.access_tokens.connections.sole
    assert_equal [ "dobase CLI", true, "write" ], [ connection.name, connection.agent, connection.permission ]
    assert_equal connection, AccessToken.authenticate(tokens["access_token"])

    travel 12.seconds do
      poll(device)
    end
    assert_equal "invalid_grant", response.parsed_body["error"], "a device code connects once"
  end

  test "the page's form sends the code back with a POST" do
    record, = Oauth::DeviceCode.issue(@client)
    sign_in_as @user
    get "/oauth/device", params: { user_code: record.user_code }
    assert_select "form[action='/oauth/device'][method=post]" do
      assert_select "input[name=user_code][value=?]", record.user_code
      assert_select "button[name=decision][value=allow]"
    end
  end

  test "no means no, and a code runs out" do
    record, device_code = Oauth::DeviceCode.issue(@client)
    sign_in_as @user
    post "/oauth/device", params: { user_code: record.user_code, decision: "deny" }
    poll({ "device_code" => device_code })
    assert_equal "access_denied", response.parsed_body["error"]

    _, late = Oauth::DeviceCode.issue(@client)
    travel 11.minutes do
      poll({ "device_code" => late })
    end
    assert_equal "expired_token", response.parsed_body["error"]
  end

  test "a wrong code, or another client's device code, gets nothing" do
    sign_in_as @user
    post "/oauth/device", params: { user_code: "XXXX-XXXX", decision: "allow" }
    assert_redirected_to new_oauth_device_path

    _, device_code = Oauth::DeviceCode.issue(@client)
    other = Oauth::Client.register(name: "Other", redirect_uris: [ "http://127.0.0.1/" ])
    post "/oauth/token", params: { grant_type: GRANT, device_code:, client_id: other.uid }
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "the metadata names the device endpoint" do
    get "/.well-known/oauth-authorization-server"
    assert_equal "http://www.example.com/oauth/device_authorization", response.parsed_body["device_authorization_endpoint"]
    assert_includes response.parsed_body["grant_types_supported"], GRANT
  end

  private

  def poll(device)
    post "/oauth/token", params: { grant_type: GRANT, device_code: device["device_code"], client_id: @client.uid }
  end
end

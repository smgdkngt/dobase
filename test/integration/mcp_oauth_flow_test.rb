# frozen_string_literal: true

require "test_helper"

# The whole round trip Claude makes: discover, register, send the person to
# sign in and allow, trade the code for tokens, call /mcp, refresh.
class McpOauthFlowTest < ActionDispatch::IntegrationTest
  CALLBACK = "https://claude.ai/api/mcp/auth_callback"

  setup do
    @user = users(:one)
    @verifier = SecureRandom.urlsafe_base64(48)
    @challenge = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(@verifier), padding: false)
  end

  test "publishes the metadata a client discovers the server with" do
    get "/.well-known/oauth-protected-resource/mcp"
    assert_response :success
    assert_equal "http://www.example.com/mcp", response.parsed_body["resource"]
    assert_equal [ "http://www.example.com" ], response.parsed_body["authorization_servers"]

    get "/.well-known/oauth-authorization-server"
    assert_equal "http://www.example.com/oauth/token", response.parsed_body["token_endpoint"]
    assert_equal [ "S256" ], response.parsed_body["code_challenge_methods_supported"]
  end

  test "a call to /mcp without a token points at the metadata" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json, headers: mcp_headers
    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"],
      'resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp"'
  end

  test "registers, signs in, allows, gets tokens, calls a tool and refreshes" do
    client_id = register

    get "/oauth/authorize", params: authorize_params(client_id)
    assert_redirected_to new_session_path

    sign_in_as @user
    get "/oauth/authorize", params: authorize_params(client_id)
    assert_response :success
    assert_includes response.body, "Connect Claude"

    post "/oauth/authorize", params: authorize_params(client_id).merge(decision: "allow", permission: "write", agent: "true")
    redirect = URI.parse(response.location)
    query = Rack::Utils.parse_query(redirect.query)
    assert_equal CALLBACK, "#{redirect.scheme}://#{redirect.host}#{redirect.path}"
    assert_equal "xyz", query["state"]
    assert_equal "http://www.example.com", query["iss"]

    post "/oauth/token", params: { grant_type: "authorization_code", code: query["code"], redirect_uri: CALLBACK,
      client_id:, code_verifier: @verifier }
    assert_response :success
    tokens = response.parsed_body
    assert_equal "Bearer", tokens["token_type"]

    connection = @user.access_tokens.connections.sole
    assert_equal "Claude", connection.name
    assert connection.agent?
    assert connection.write?
    assert_in_delta 30.days.from_now, connection.expires_at, 1.minute

    session_id = mcp_session(tokens["access_token"])
    names = mcp_request(tokens["access_token"], session_id, "tools/list").dig("result", "tools").pluck("name")
    assert_includes names, "card_show"

    tools = mcp_call(tokens["access_token"], session_id, "tool_list")
    assert_includes tools["items"].pluck("id"), tools(:project_board).id
    assert_equal "ok", Mcp::ToolCall.last.outcome
    assert_equal connection, Mcp::ToolCall.last.access_token

    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"], client_id: }
    assert_response :success
    fresh = response.parsed_body
    assert_not_equal tokens["access_token"], fresh["access_token"]

    post "/mcp", params: { jsonrpc: "2.0", id: 9, method: "ping" }.to_json, headers: mcp_headers(tokens["access_token"], session_id)
    assert_response :unauthorized, "the old access token ends with the refresh"

    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"], client_id: }
    assert_response :bad_request, "a refresh token works once"
    assert_not AccessToken.exists?(connection.id), "and a second use ends the connection"
    post "/mcp", params: { jsonrpc: "2.0", id: 10, method: "ping" }.to_json, headers: mcp_headers(fresh["access_token"])
    assert_response :unauthorized
  end

  test "denying sends the client away with nothing" do
    client_id = register
    sign_in_as @user
    post "/oauth/authorize", params: authorize_params(client_id).merge(decision: "deny")
    assert_equal "access_denied", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
    assert_empty @user.access_tokens.connections
  end

  test "a client that isn't known, or a redirect it didn't register, is never redirected to" do
    client_id = register
    sign_in_as @user

    get "/oauth/authorize", params: authorize_params(client_id).merge(redirect_uri: "https://claude.ai/elsewhere")
    assert_response :bad_request
    get "/oauth/authorize", params: authorize_params("nobody")
    assert_response :bad_request
  end

  test "registration takes only Claude's addresses and this computer's" do
    post "/oauth/register", params: { client_name: "Evil", redirect_uris: [ "https://evil.example/callback" ] }, as: :json
    assert_response :bad_request

    post "/oauth/register", params: { client_name: "Lookalike", redirect_uris: [ "https://claude.ai.evil.example/cb" ] }, as: :json
    assert_response :bad_request

    post "/oauth/register", params: { client_name: "dobase CLI", redirect_uris: [ "http://127.0.0.1:53682/callback" ] }, as: :json
    assert_response :created
  end

  test "PKCE without S256 is refused" do
    client_id = register
    sign_in_as @user
    get "/oauth/authorize", params: authorize_params(client_id).merge(code_challenge_method: "plain")
    assert_equal "invalid_request", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
  end

  test "a code works once, with its verifier, and a second try ends the connection it made" do
    client = Oauth::Client.register(name: "Claude", redirect_uris: [ CALLBACK ])
    _, code = Oauth::AuthorizationCode.issue(client:, user: @user, redirect_uri: CALLBACK, code_challenge: @challenge,
      permission: "write", agent: true)

    post "/oauth/token", params: { grant_type: "authorization_code", code:, redirect_uri: CALLBACK, client_id: client.uid,
      code_verifier: "wrong-#{@verifier}" }
    assert_response :bad_request

    _, code = Oauth::AuthorizationCode.issue(client:, user: @user, redirect_uri: CALLBACK, code_challenge: @challenge,
      permission: "write", agent: true)
    post "/oauth/token", params: { grant_type: "authorization_code", code:, redirect_uri: CALLBACK, client_id: client.uid,
      code_verifier: @verifier }
    assert_response :success
    connection = @user.access_tokens.connections.sole

    post "/oauth/token", params: { grant_type: "authorization_code", code:, redirect_uri: CALLBACK, client_id: client.uid,
      code_verifier: @verifier }
    assert_response :bad_request
    assert_not AccessToken.exists?(connection.id)
  end

  test "a code from another client is no use" do
    client = Oauth::Client.register(name: "Claude", redirect_uris: [ CALLBACK ])
    other = Oauth::Client.register(name: "Other", redirect_uris: [ CALLBACK ])
    _, code = Oauth::AuthorizationCode.issue(client:, user: @user, redirect_uri: CALLBACK, code_challenge: @challenge,
      permission: "write", agent: true)

    post "/oauth/token", params: { grant_type: "authorization_code", code:, redirect_uri: CALLBACK, client_id: other.uid,
      code_verifier: @verifier }
    assert_response :bad_request
  end

  test "revoking either token ends the connection" do
    client = Oauth::Client.register(name: "Claude", redirect_uris: [ CALLBACK ])
    connection = connect(client)
    _, access, = Oauth::Grant.issue(connection)

    post "/oauth/revoke", params: { token: access, client_id: client.uid }
    assert_response :success
    assert_not AccessToken.exists?(connection.id)
  end

  test "a connection lasts thirty days from consent, however often it is refreshed" do
    client = Oauth::Client.register(name: "Claude", redirect_uris: [ CALLBACK ])
    connection = connect(client)
    _, access, refresh = Oauth::Grant.issue(connection)

    travel 29.days + 23.hours do
      assert Oauth::Grant.refresh(refresh, client:)
    end
    travel 30.days + 1.minute do
      assert_nil AccessToken.authenticate(access)
      post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: refresh, client_id: client.uid }
      assert_response :bad_request
    end
  end

  test "a new password ends every connection, and leaves personal tokens" do
    personal = @user.access_tokens.create!(name: "Script")
    connection = connect(Oauth::Client.register(name: "Claude", redirect_uris: [ CALLBACK ]))

    @user.update!(password: "a new password 123")
    assert_not AccessToken.exists?(connection.id)
    assert AccessToken.exists?(personal.id)
  end

  test "switching MCP off ends the connections and refuses new ones" do
    client_id = register
    connect(Oauth::Client.find_by!(uid: client_id))
    @user.update!(mcp_enabled: false)
    assert_empty @user.access_tokens.connections

    sign_in_as @user
    get "/oauth/authorize", params: authorize_params(client_id)
    assert_response :forbidden
  end

  test "a personal token works on /mcp as well" do
    token = @user.access_tokens.create!(name: "Routine", permission: "read").token
    session_id = mcp_session(token)
    assert_equal tools(:project_board).id, mcp_call(token, session_id, "tool_show", tool_id: tools(:project_board).id)["id"]
  end

  test "a session belongs to the token that started it" do
    token = @user.access_tokens.create!(name: "One").token
    other = users(:two).access_tokens.create!(name: "Two").token
    session_id = mcp_session(token)

    post "/mcp", params: { jsonrpc: "2.0", id: 5, method: "tools/list" }.to_json, headers: mcp_headers(other, session_id)
    assert_response :not_found
  end

  test "batches and oversized bodies are refused" do
    token = @user.access_tokens.create!(name: "One").token
    session_id = mcp_session(token)

    post "/mcp", params: [ { jsonrpc: "2.0", id: 1, method: "ping" } ].to_json, headers: mcp_headers(token, session_id)
    assert_equal(-32_600, response.parsed_body.dig("error", "code"))

    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "ping", params: { pad: "x" * 1.1.megabytes } }.to_json,
      headers: mcp_headers(token, session_id)
    assert_response :content_too_large
  end

  private

  def register
    post "/oauth/register", params: { client_name: "Claude", redirect_uris: [ CALLBACK ] }, as: :json
    assert_response :created
    response.parsed_body["client_id"]
  end

  def authorize_params(client_id)
    { client_id:, redirect_uri: CALLBACK, response_type: "code", code_challenge: @challenge,
      code_challenge_method: "S256", state: "xyz" }
  end

  def connect(client)
    @user.access_tokens.create!(name: client.name, oauth_client: client, permission: "write",
      expires_at: AccessToken::CONNECTION_LIFETIME.from_now)
  end
end

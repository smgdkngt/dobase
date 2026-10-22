# frozen_string_literal: true

require "test_helper"

class Profiles::McpAccessesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @client = Oauth::Client.register(name: "Claude", redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ])
    @connection = @user.access_tokens.create!(name: "Claude", oauth_client: @client, expires_at: 30.days.from_now)
    sign_in_as @user
  end

  test "the API tab lists a connection with the tokens, and the MCP address and calls" do
    Mcp::ToolCall.create!(user: @user, access_token: @connection, tool: "card_show", outcome: "ok")

    get edit_profile_path(tab: "api")
    assert_response :success
    assert_includes response.body, "Connected by MCP"
    assert_includes response.body, "http://www.example.com/mcp"
    assert_includes response.body, "card_show"
  end

  test "switching connections off ends them, and on again lets new ones in" do
    patch profile_mcp_access_path, params: { enabled: "false" }
    assert_redirected_to edit_profile_path(tab: "api")
    assert_not @user.reload.mcp_enabled?
    assert_not AccessToken.exists?(@connection.id)

    patch profile_mcp_access_path, params: { enabled: "true" }
    assert @user.reload.mcp_enabled?
  end

  test "a token can't switch it" do
    patch profile_mcp_access_path, params: { enabled: "false" }, headers: api_headers(@user), as: :json
    assert_response :forbidden
    assert @user.reload.mcp_enabled?
  end
end

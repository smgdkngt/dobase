# frozen_string_literal: true

require "test_helper"

class PurgeMcpJobTest < ActiveJob::TestCase
  CALLBACK = "https://claude.ai/api/mcp/auth_callback"

  test "clears old calls, dead codes and pairs, ended connections and clients nobody said yes to" do
    user = users(:one)
    used = Oauth::Client.register(name: "Claude", redirect_uris: [ CALLBACK ])
    unused = Oauth::Client.register(name: "Nobody", redirect_uris: [ CALLBACK ])
    connection = user.access_tokens.create!(name: "Claude", oauth_client: used, expires_at: 30.days.from_now)
    ended = user.access_tokens.create!(name: "Claude", oauth_client: used, expires_at: 1.minute.from_now)
    old_call = Mcp::ToolCall.create!(user:, tool: "whoami", outcome: "ok", created_at: 31.days.ago)
    new_call = Mcp::ToolCall.create!(user:, tool: "whoami", outcome: "ok")
    _, = Oauth::AuthorizationCode.issue(client: used, user:, redirect_uri: CALLBACK, code_challenge: "x", permission: "read", agent: true)
    revoked, = Oauth::Grant.issue(connection)
    revoked.update!(revoked_at: 2.days.ago)
    live, = Oauth::Grant.issue(connection)

    travel 2.days do
      PurgeMcpJob.perform_now
    end

    assert_not Mcp::ToolCall.exists?(old_call.id)
    assert Mcp::ToolCall.exists?(new_call.id)
    assert_empty Oauth::AuthorizationCode.all
    assert_not Oauth::Grant.exists?(revoked.id)
    assert_not Oauth::Grant.exists?(live.id), "an hour's pair is long gone after two days"
    assert AccessToken.exists?(connection.id)
    assert_not AccessToken.exists?(ended.id)
    assert Oauth::Client.exists?(used.id)
    assert_not Oauth::Client.exists?(unused.id)
  end
end

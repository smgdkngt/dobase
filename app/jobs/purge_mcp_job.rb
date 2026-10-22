# frozen_string_literal: true

# What MCP and OAuth leave behind: calls older than thirty days, codes and
# token pairs that can't be used any more, and clients nobody said yes to
class PurgeMcpJob < ApplicationJob
  queue_as :default

  def perform
    Mcp::ToolCall.where(created_at: ...Mcp::ToolCall::KEPT.ago).delete_all
    Oauth::AuthorizationCode.where(expires_at: ...1.day.ago).delete_all
    Oauth::Grant.where(expires_at: ...1.day.ago).or(Oauth::Grant.where(revoked_at: ...1.day.ago)).delete_all
    AccessToken.connections.where(expires_at: ...Time.current).destroy_all
    Oauth::Client.unused.destroy_all
  end
end

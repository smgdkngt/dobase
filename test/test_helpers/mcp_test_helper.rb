module McpTestHelper
  PROTOCOL = "2025-06-18"

  # Starts an MCP session on /mcp with a token and returns its id
  def mcp_session(token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: "test", version: "1" } } }.to_json,
      headers: mcp_headers(token)
    assert_response :success
    session_id = response.headers["Mcp-Session-Id"]
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: mcp_headers(token, session_id)
    session_id
  end

  def mcp_request(token, session_id, method, params = {}, id: rand(1_000_000))
    post "/mcp", params: { jsonrpc: "2.0", id:, method:, params: }.to_json, headers: mcp_headers(token, session_id)
    response.parsed_body
  end

  # The result of a tool call: its structured content, or the error text when it failed
  def mcp_call(token, session_id, name, **arguments)
    result = mcp_request(token, session_id, "tools/call", { name:, arguments: })["result"]
    result["isError"] ? result.dig("content", 0, "text") : result["structuredContent"]
  end

  def mcp_headers(token = nil, session_id = nil)
    { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => PROTOCOL, "Authorization" => token && "Bearer #{token}",
      "Mcp-Session-Id" => session_id }.compact
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include McpTestHelper
end

# frozen_string_literal: true

require "test_helper"
require "puma"
require "puma/server"
require "net/http"

# Live updates over a real socket, through a real Puma with as few threads as
# production has: the stream is server-sent events, and an open stream holds
# none of Puma's threads.
class McpLiveStreamTest < ActionDispatch::IntegrationTest
  setup do
    # Other tests load WebMock, which then refuses every real connection
    WebMock.disable_net_connect!(allow_localhost: true) if defined?(WebMock)
    # Puma's threads and Action Cable's share the test's connection (lock_threads), so they see its fixtures
    @server = Puma::Server.new(Rails.application, nil, min_threads: 1, max_threads: 3, log_writer: Puma::LogWriter.null)
    @port = @server.add_tcp_listener("127.0.0.1", 0).addr[1]
    @server.run
    @user = users(:one)
    @token = @user.access_tokens.create!(name: "CLI", permission: "write").token
  end

  teardown do
    @streams&.each(&:kill)
    @server&.stop(true)
    WebMock.allow_net_connect! if defined?(WebMock)
  end

  test "a subscribed session hears its tool change and its new events, while Puma stays free" do
    board = tools(:project_board)
    session = initialize_session
    lines = open_stream(session)

    assert_equal({}, rpc(session, "resources/subscribe", uri: "dobase://tools/#{board.id}")["result"])
    assert_equal({}, rpc(session, "resources/subscribe", uri: "dobase://events")["result"])

    # With the stream open, three more requests at once still get through three threads
    3.times.map { Thread.new { Net::HTTP.get_response(URI("http://127.0.0.1:#{@port}/up")).code } }.each { assert_equal "200", it.value }

    result = rpc(session, "tools/call", name: "card_create", arguments: { tool_id: board.id, title: "Heard live" })
    assert_equal "Heard live", result.dig("result", "structuredContent", "title")

    heard = 2.times.map { next_notification(lines) }
    assert_equal [ "dobase://events", "dobase://tools/#{board.id}" ].sort, heard.map { it.dig("params", "uri") }.sort
    assert heard.all? { it["method"] == "notifications/resources/updated" }
  end

  test "a tool the person doesn't have can't be subscribed to" do
    session = initialize_session
    response = rpc(session, "resources/subscribe", uri: "dobase://tools/#{tools(:other_todos).id}")
    assert_equal(-32_602, response.dig("error", "code"))
  end

  test "revoking the token ends its stream" do
    session = initialize_session
    lines = open_stream(session)
    rpc(session, "resources/subscribe", uri: "dobase://events")

    @user.access_tokens.find_by!(name: "CLI").destroy
    assert_equal :closed, Timeout.timeout(5) { lines.pop }
  end

  private

  def http
    Net::HTTP.new("127.0.0.1", @port).tap { it.read_timeout = 10 }
  end

  def headers(session = nil)
    { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => McpTestHelper::PROTOCOL, "Mcp-Session-Id" => session }.compact
  end

  def initialize_session
    response = http.post("/mcp", { jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: McpTestHelper::PROTOCOL, capabilities: {}, clientInfo: { name: "test", version: "1" } } }.to_json, headers)
    session = response["mcp-session-id"]
    http.post("/mcp", { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers(session))
    session
  end

  def rpc(session, method, **params)
    JSON.parse(http.post("/mcp", { jsonrpc: "2.0", id: rand(1_000_000), method:, params: }.to_json, headers(session)).body)
  end

  # The stream's data lines as they come, and :closed when it ends. Read off a
  # plain socket: WebMock's Net::HTTP waits for the whole body, which a stream never has.
  def open_stream(session)
    lines = Queue.new
    ready = Queue.new
    (@streams ||= []) << Thread.new do
      socket = TCPSocket.new("127.0.0.1", @port)
      request = headers(session).merge("Accept" => "text/event-stream", "Host" => "127.0.0.1:#{@port}").except("Content-Type")
      socket.write("GET /mcp HTTP/1.1\r\n#{request.map { |name, value| "#{name}: #{value}\r\n" }.join}\r\n")
      ready << socket.gets.to_s.split[1]
      while (line = socket.gets)
        lines << line.delete_prefix("data: ").strip if line.start_with?("data: ")
      end
      lines << :closed
    rescue IOError, Errno::ECONNRESET
      lines << :closed
    end
    assert_equal "200", Timeout.timeout(5) { ready.pop }
    lines
  end

  def next_notification(lines)
    JSON.parse(Timeout.timeout(5) { lines.pop })
  end
end

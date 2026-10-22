# frozen_string_literal: true

module Mcp
  # `/mcp`: Streamable HTTP, mounted as a Rack app so that the SDK's answers
  # reach Puma as the SDK makes them. In front of the SDK's transport it checks
  # the access token (any token: a personal one, or a connection made by
  # OAuth), counts requests per person and refuses oversized bodies.
  #
  # Sessions live in this process (production runs one Puma process), so a
  # deploy ends them: a client then gets 404 and starts a new session, as the
  # protocol says it should.
  #
  # A session's GET stream (server-sent events, for Mcp::Live) is handed to
  # Puma as a partial hijack: Puma writes the headers, gives the socket to the
  # SDK and goes on, so an open stream holds none of its three threads.
  class Endpoint
    REQUESTS_PER_MINUTE = 120
    MAX_BODY_BYTES = 8.megabytes # files come along as base64
    BUILDING = Monitor.new # reentrant: building the transport asks for the server

    def self.call(env)
      new.call(env)
    end

    # One for the process, since it holds the sessions
    def self.transport
      @transport || BUILDING.synchronize { @transport ||= build_transport }
    end

    def self.live
      @live || BUILDING.synchronize { @live ||= Live.new(transport) }
    end

    # Only when MCP has been used in this process: nothing to close otherwise
    def self.running_live
      @live
    end

    def self.build_transport
      MCP::Server::Transports::StreamableHTTPTransport.new(
        Server.instance,
        enable_json_response: true,
        # A request without a bearer token goes no further, so a page that
        # rebinds a name to this server gets nothing it could use
        dns_rebinding_protection: false,
        max_request_bytes: MAX_BODY_BYTES,
        max_sessions: 1_000,
        serve_subscriptions_listen: false
      ).tap { Server.instance.transport = it }
    end

    def call(env)
      request = ActionDispatch::Request.new(env)
      return [ 403, { "content-type" => "application/json" }, [ { error: "Not available in the demo" }.to_json ] ] if Demo.enabled?
      return [ 405, { "allow" => "GET, POST, DELETE" }, [] ] unless request.get? || request.post? || request.delete?
      return payload_too_large if request.content_length.to_i > MAX_BODY_BYTES

      token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
      access_token = AccessToken.authenticate(token)
      return unauthorized(request) if access_token.nil?
      return too_many_requests if over_the_limit?(access_token)

      access_token.record_usage
      access_token.oauth_client&.touch_last_used
      Current.access_token = access_token
      session_id = request.headers["Mcp-Session-Id"]
      env[MCP::Server::OAuth::ENV_KEY] = Server.auth_info(access_token, token,
        host: request.host_with_port, https: request.ssl?, remote_ip: request.remote_ip, session_id:)
      status, headers, body = self.class.transport.call(env)
      if request.delete? && status == 200
        self.class.live.end_session(session_id)
      elsif (started = headers["mcp-session-id"]) && session_id.nil?
        self.class.live.track(started, access_token.id)
      end
      stream(status, headers, body)
    end

    private

    # The SDK answers a GET with a body that takes the socket (Rack's streaming
    # body). Rails' middleware wraps bodies, which would hide that from Puma,
    # so it goes to Puma as the response's hijack instead.
    def stream(status, headers, body)
      return [ status, headers, body ] unless body.respond_to?(:call) && !body.respond_to?(:each)

      [ status, headers.merge("rack.hijack" => body, "x-accel-buffering" => "no"), [] ]
    end

    def unauthorized(request)
      metadata = "#{request.base_url}/.well-known/oauth-protected-resource/mcp"
      [ 401, { "content-type" => "application/json", "www-authenticate" => %(Bearer resource_metadata="#{metadata}") },
        [ { error: "invalid_token" }.to_json ] ]
    end

    def over_the_limit?(access_token)
      count = Rails.cache.increment("mcp:requests:#{access_token.user_id}:#{Time.current.to_i / 60}", 1, expires_in: 2.minutes)
      count.to_i > REQUESTS_PER_MINUTE
    end

    def too_many_requests
      [ 429, { "content-type" => "application/json", "retry-after" => "60" },
        [ { jsonrpc: "2.0", id: nil, error: { code: -32_000, message: "Too many requests, try again in a minute" } }.to_json ] ]
    end

    def payload_too_large
      [ 413, { "content-type" => "application/json" },
        [ { jsonrpc: "2.0", id: nil, error: { code: -32_600, message: "Request too large" } }.to_json ] ]
    end
  end
end

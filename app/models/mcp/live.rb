# frozen_string_literal: true

module Mcp
  # Live updates over MCP. A session subscribes to a resource and hears
  # `notifications/resources/updated` on its GET stream when it changes:
  #
  # - `dobase://events`: there is a new event for this person (what
  #   `dobase events --follow` listens for); `event_list` then says what.
  # - `dobase://tools/<id>`: something in that tool changed (what an open page
  #   of it hears and draws itself again for).
  #
  # Both are the signals Action Cable already carries (`Event#signal`,
  # `Tool#announce_change`), heard here on its pub/sub, so a change made in a
  # job reaches a stream in the web process as it reaches a page. Like those,
  # a notification says only that something changed, never what: the client
  # asks, and gets what it may see. One pub/sub subscription per channel for
  # the whole process, whatever the number of sessions on it.
  class Live
    EVENTS = "dobase://events"
    TOOL = %r{\Adobase://tools/(\d+)\z}

    # What one token may hold at once; past it the oldest of its sessions ends
    SESSIONS_PER_TOKEN = 20

    class Refused < StandardError; end

    def initialize(transport)
      @transport = transport
      @mutex = Mutex.new
      # channel => { session_id => [uri, user_id] }
      @listeners = Hash.new { |hash, channel| hash[channel] = {} }
      # channel => what pub/sub calls, which it is unsubscribed by
      @callbacks = {}
      # session_id => the access token that started it, oldest first
      @sessions = {}
    end

    # A session started with this token (at initialize)
    def track(session_id, access_token_id)
      surplus = @mutex.synchronize do
        @sessions[session_id] = access_token_id
        own = @sessions.select { |_, token_id| token_id == access_token_id }.keys
        own.first([ own.size - SESSIONS_PER_TOKEN, 0 ].max)
      end
      surplus.each { close(it) }
    end

    # A token that is revoked takes its sessions and their streams along at once
    def close_token(access_token_id)
      @mutex.synchronize { @sessions.select { |_, token_id| token_id == access_token_id }.keys }.each { close(it) }
    end

    def close(session_id)
      end_session(session_id)
      @transport.send(:cleanup_session, session_id)
    end

    def subscribe(session_id, uri, user)
      raise Refused, "No session" if session_id.blank?

      channel = channel_for(uri, user)
      callback = @mutex.synchronize do
        fresh = !@listeners.key?(channel)
        @listeners[channel][session_id] = [ uri, user.id ]
        @callbacks[channel] = ->(message) { deliver(channel, message) } if fresh
      end
      ActionCable.server.pubsub.subscribe(channel, callback) if callback
    end

    def unsubscribe(session_id, uri, user)
      forget(channel_for(uri, user)) { |sessions| sessions.delete(session_id) }
    end

    def end_session(session_id)
      @mutex.synchronize do
        @sessions.delete(session_id)
        @listeners.keys
      end.each { |channel| forget(channel) { it.delete(session_id) } }
    end

    def subscribed?(session_id, uri)
      @mutex.synchronize { @listeners.values.any? { it[session_id]&.first == uri } }
    end

    private

    def channel_for(uri, user)
      if uri == EVENTS
        EventsChannel.stream_name(user.id)
      elsif (id = uri.to_s[TOOL, 1]) && (tool = ::Tool.find_by(id:)) && tool.accessible_by?(user)
        PresenceChannel.broadcasting_for(tool)
      else
        raise Refused, "No resource #{uri}: subscribe to #{EVENTS} or dobase://tools/<id> of a tool you have"
      end
    end

    def deliver(channel, message)
      payload = JSON.parse(message) rescue {}
      return if channel.start_with?("presence:") && payload["type"] != "changed"

      listeners = @mutex.synchronize { @listeners[channel].dup }
      listeners.each do |session_id, (uri, user_id)|
        next close(session_id) unless token_valid?(session_id)
        next forget(channel) { it.delete(session_id) } unless still_allowed?(uri, user_id) && session?(session_id)

        @transport.send_notification("notifications/resources/updated", { uri: }, session_id:)
      end
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { mcp_live: channel })
    end

    # A connection that ended (expired, or revoked in a process that couldn't close it here) hears nothing more
    def token_valid?(session_id)
      token_id = @mutex.synchronize { @sessions[session_id] }
      return true unless token_id

      ActiveRecord::Base.connection_pool.with_connection do
        AccessToken.where(id: token_id).where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
      end
    end

    # Someone taken off a tool stops hearing of it
    def still_allowed?(uri, user_id)
      id = uri[TOOL, 1]
      return true unless id

      ActiveRecord::Base.connection_pool.with_connection { Collaborator.exists?(tool_id: id, user_id:) }
    end

    # The transport ends sessions on its own (idle, deleted): a session it no longer has is let go here too
    def session?(session_id)
      @transport.send(:session_exists?, session_id)
    end

    def forget(channel)
      callback = @mutex.synchronize do
        next unless @listeners.key?(channel)

        yield @listeners[channel]
        next unless @listeners[channel].empty?

        @listeners.delete(channel)
        @callbacks.delete(channel)
      end
      ActionCable.server.pubsub.unsubscribe(channel, callback) if callback
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class Mcp::LiveTest < ActiveSupport::TestCase
  # Stands in for the SDK's transport: keeps what it was asked to send
  class FakeTransport
    attr_reader :sent, :cleaned
    attr_accessor :sessions

    def initialize
      @sent = []
      @cleaned = []
      @sessions = []
    end

    def send_notification(method, params, session_id:)
      @sent << [ session_id, method, params[:uri] ]
      true
    end

    def session_exists?(session_id) = sessions.include?(session_id)

    def cleanup_session(session_id)
      @cleaned << session_id
      sessions.delete(session_id)
    end
  end

  setup do
    @user = users(:one)
    @transport = FakeTransport.new
    @transport.sessions = %w[a b]
    @live = Mcp::Live.new(@transport)
  end

  teardown do
    @live.end_session("a")
    @live.end_session("b")
  end

  test "a subscribed session hears that its person's events or its tool changed" do
    board = tools(:project_board)
    @live.subscribe("a", "dobase://events", @user)
    @live.subscribe("b", "dobase://tools/#{board.id}", @user)

    @live.send(:deliver, EventsChannel.stream_name(@user.id), { id: 5 }.to_json)
    @live.send(:deliver, PresenceChannel.broadcasting_for(board), { type: "changed", tool_id: board.id }.to_json)
    @live.send(:deliver, PresenceChannel.broadcasting_for(board), { type: "here" }.to_json)

    assert_equal [ [ "a", "notifications/resources/updated", "dobase://events" ],
                   [ "b", "notifications/resources/updated", "dobase://tools/#{board.id}" ] ], @transport.sent
  end

  test "a tool someone doesn't have, or a resource that isn't one, is refused" do
    assert_raises(Mcp::Live::Refused) { @live.subscribe("a", "dobase://tools/#{tools(:other_todos).id}", @user) }
    assert_raises(Mcp::Live::Refused) { @live.subscribe("a", "dobase://tools/0", @user) }
    assert_raises(Mcp::Live::Refused) { @live.subscribe("a", "https://example.com", @user) }
  end

  test "someone taken off a tool stops hearing of it" do
    board = tools(:project_board)
    @live.subscribe("a", "dobase://tools/#{board.id}", @user)
    Collaborator.where(tool: board, user: @user).delete_all

    @live.send(:deliver, PresenceChannel.broadcasting_for(board), { type: "changed" }.to_json)
    assert_empty @transport.sent
    assert_not @live.subscribed?("a", "dobase://tools/#{board.id}")
  end

  test "a session the transport ended is let go" do
    @live.subscribe("a", "dobase://events", @user)
    @transport.sessions = []
    @live.send(:deliver, EventsChannel.stream_name(@user.id), "{}")
    assert_empty @transport.sent
    assert_not @live.subscribed?("a", "dobase://events")
  end

  test "unsubscribing and ending a session stop it" do
    @live.subscribe("a", "dobase://events", @user)
    @live.subscribe("b", "dobase://events", @user)
    @live.unsubscribe("a", "dobase://events", @user)
    @live.end_session("b")
    @live.send(:deliver, EventsChannel.stream_name(@user.id), "{}")
    assert_empty @transport.sent
  end

  test "a revoked token takes its sessions along, and an ended one hears nothing" do
    token = @user.access_tokens.create!(name: "CLI")
    @live.track("a", token.id)
    @live.subscribe("a", "dobase://events", @user)
    @live.close_token(token.id)
    assert_equal [ "a" ], @transport.cleaned
    assert_not @live.subscribed?("a", "dobase://events")

    @live.track("b", token.id)
    @live.subscribe("b", "dobase://events", @user)
    token.update!(expires_at: 1.minute.ago)
    @live.send(:deliver, EventsChannel.stream_name(@user.id), "{}")
    assert_empty @transport.sent
    assert_includes @transport.cleaned, "b"
  end

  test "one token holds twenty sessions at most, and the oldest goes first" do
    token = @user.access_tokens.create!(name: "Busy")
    21.times { @live.track("s#{it}", token.id) }
    assert_equal [ "s0" ], @transport.cleaned
  end
end

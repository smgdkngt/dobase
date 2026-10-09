# frozen_string_literal: true

require "test_helper"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    include ActionCable::TestHelper

    setup do
      @user = users(:one)
    end

    test "a page connects by its session" do
      session = @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      cookies.signed[:session_id] = session.id

      connect

      assert_equal @user, connection.current_user
      assert_nil connection.access_token
    end

    test "a listener connects by its access token, read-only ones too" do
      token = @user.access_tokens.create!(name: "Listener", permission: "read")

      connect headers: { "Authorization" => "Bearer #{token.token}" }

      assert_equal @user, connection.current_user
      assert_equal token, connection.access_token
      assert_not_nil token.reload.last_used_at
    end

    test "a token that doesn't exist is turned away, also beside a good session" do
      session = @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      cookies.signed[:session_id] = session.id

      assert_reject_connection { connect headers: { "Authorization" => "Bearer dobase_nothing" } }
    end

    test "nobody is turned away" do
      assert_reject_connection { connect }
    end

    test "a token in the address is no token" do
      token = @user.access_tokens.create!(name: "Listener")

      assert_reject_connection { connect params: { token: token.token, access_token: token.token } }
    end

    test "revoking a token closes its connections, and nobody else's" do
      token = @user.access_tokens.create!(name: "Listener")
      other = @user.access_tokens.create!(name: "Another")
      connect headers: { "Authorization" => "Bearer #{token.token}" }
      mine = "action_cable/#{connection.connection_identifier}"
      connect headers: { "Authorization" => "Bearer #{other.token}" }
      others = "action_cable/#{connection.connection_identifier}"
      assert_not_equal mine, others

      assert_no_broadcasts(others) do
        assert_broadcast_on(mine, type: "disconnect", reconnect: false) { token.destroy! }
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Tools
  module Rooms
    class TokensControllerTest < ActionDispatch::IntegrationTest
      LIVEKIT_ENV_KEYS = %w[LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET].freeze

      setup do
        sign_in_as users(:one)
        @tool = tools(:my_room)
        @previous_livekit_env = LIVEKIT_ENV_KEYS.index_with { |key| ENV[key] }
      end

      teardown do
        @previous_livekit_env.each { |key, value| ENV[key] = value }
      end

      test "returns a clear error when LiveKit isn't configured" do
        LIVEKIT_ENV_KEYS.each { |key| ENV.delete(key) }

        post tool_room_tokens_path(@tool), as: :json

        assert_response :service_unavailable
        assert_match(/LIVEKIT_URL/, response.parsed_body["error"])
      end

      test "returns a clear error when only some LiveKit env vars are set" do
        ENV["LIVEKIT_URL"] = "ws://localhost:7880"
        ENV.delete("LIVEKIT_API_KEY")
        ENV.delete("LIVEKIT_API_SECRET")

        post tool_room_tokens_path(@tool), as: :json

        assert_response :service_unavailable
        assert response.parsed_body["error"].present?
      end

      test "creates a token when LiveKit is configured" do
        ENV["LIVEKIT_URL"] = "ws://localhost:7880"
        ENV["LIVEKIT_API_KEY"] = "devkey"
        ENV["LIVEKIT_API_SECRET"] = "devsecret"

        post tool_room_tokens_path(@tool), as: :json

        assert_response :success
        body = response.parsed_body
        assert body["token"].present?
        assert_equal "ws://localhost:7880", body["url"]
        assert_equal @tool.room.livekit_room_name, body["room_name"]
      end

      test "requires tool access" do
        ENV["LIVEKIT_URL"] = "ws://localhost:7880"
        ENV["LIVEKIT_API_KEY"] = "devkey"
        ENV["LIVEKIT_API_SECRET"] = "devsecret"
        sign_out
        sign_in_as users(:two)

        post tool_room_tokens_path(@tool), as: :json

        assert_response :forbidden
      end

      test "requires authentication" do
        sign_out

        post tool_room_tokens_path(@tool), as: :json

        assert_response :unauthorized
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  module Rooms
    class TokensController < ApplicationController
      include ToolScoped

      def create
        return render_not_configured unless livekit_configured?

        room = @tool.room
        render json: {
          token: room.generate_token_for(current_user),
          url: ENV["LIVEKIT_URL"],
          room_name: room.livekit_room_name
        }
      rescue StandardError => e
        Rails.logger.error("Room token generation failed: #{e.class}: #{e.message}")
        render json: { error: "Couldn't start the call. Try again in a moment." }, status: :internal_server_error
      end

      private

      def livekit_configured?
        ENV["LIVEKIT_URL"].present? && ENV["LIVEKIT_API_KEY"].present? && ENV["LIVEKIT_API_SECRET"].present?
      end

      def render_not_configured
        render json: {
          error: "Video calls aren't set up on this server yet. Ask an administrator to set " \
                 "LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET."
        }, status: :service_unavailable
      end
    end
  end
end

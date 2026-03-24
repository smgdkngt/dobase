# frozen_string_literal: true

module Tools
  module Rooms
    class TokensController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def create
        room = @tool.room
        token = room.generate_token_for(current_user)
        livekit_url = ENV.fetch("LIVEKIT_URL", "ws://localhost:7880")

        broadcast_room_activity

        render json: {
          token: token,
          url: livekit_url,
          room_name: room.livekit_room_name
        }
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def broadcast_room_activity
        @tool.users.where.not(id: current_user.id).find_each do |user|
          ActionCable.server.broadcast("notifications:#{user.id}", {
            tool_id: @tool.id
          })
        end
      end
    end
  end
end

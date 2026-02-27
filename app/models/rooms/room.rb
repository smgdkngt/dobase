# frozen_string_literal: true

module Rooms
  class Room < ApplicationRecord
    self.table_name = "rooms"

    belongs_to :tool

    validates :tool_id, uniqueness: { message: "already has a room" }

    def livekit_room_name
      "room-#{tool_id}"
    end

    def generate_token_for(user)
      token = LiveKit::AccessToken.new(
        api_key: ENV["LIVEKIT_API_KEY"],
        api_secret: ENV["LIVEKIT_API_SECRET"],
        identity: user.id.to_s,
        name: user.name,
        ttl: 6.hours.to_i
      )
      token.add_grant(LiveKit::VideoGrant.new(roomJoin: true, room: livekit_room_name))
      token.to_jwt
    end
  end
end

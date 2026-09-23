# frozen_string_literal: true

require "test_helper"

module Rooms
  class RoomTest < ActiveSupport::TestCase
    test "belongs to a tool" do
      room = rooms(:team_standup)
      assert_equal tools(:my_room), room.tool
    end

    test "livekit_room_name is deterministic" do
      room = rooms(:team_standup)
      assert_equal "room-#{room.tool_id}", room.livekit_room_name
    end

    test "livekit_room_name starts with LIVEKIT_ROOM_PREFIX, so apps can share a LiveKit server" do
      room = rooms(:team_standup)
      previous, ENV["LIVEKIT_ROOM_PREFIX"] = ENV["LIVEKIT_ROOM_PREFIX"], "demo-"

      assert_equal "demo-room-#{room.tool_id}", room.livekit_room_name
    ensure
      ENV["LIVEKIT_ROOM_PREFIX"] = previous
    end

    test "validates uniqueness of tool" do
      room = rooms(:team_standup)
      duplicate = Rooms::Room.new(tool: room.tool)
      assert_not duplicate.valid?
    end

    test "auto-creates room when room tool is created" do
      tool = Tool.create!(name: "New Room", tool_type: tool_types(:room), owner: users(:one))
      assert_not_nil tool.room
      assert_equal "room-#{tool.id}", tool.room.livekit_room_name
    end
  end
end

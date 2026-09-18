# frozen_string_literal: true

require "test_helper"

module Tools
  module Rooms
    class ActivitiesControllerTest < ActionDispatch::IntegrationTest
      include ActionCable::TestHelper

      setup do
        @user = users(:one)
        @other_user = users(:two)
        sign_in_as @user
        @tool = tools(:my_room)
        @tool.collaborators.create!(user: @other_user, role: "collaborator")
      end

      test "create broadcasts an active room_activity ping to other collaborators, not to self" do
        assert_broadcast_on("notifications:#{@other_user.id}", type: "room_activity", tool_id: @tool.id, active: true) do
          assert_no_broadcasts("notifications:#{@user.id}") do
            post tool_room_activity_path(@tool), as: :json
          end
        end
        assert_response :no_content
      end

      test "destroy broadcasts an inactive room_activity ping when the call is empty" do
        assert_broadcast_on("notifications:#{@other_user.id}", type: "room_activity", tool_id: @tool.id, active: false) do
          delete tool_room_activity_path(@tool), as: :json
        end
        assert_response :no_content
      end

      test "destroy keeps the indicator active while participants remain" do
        assert_broadcast_on("notifications:#{@other_user.id}", type: "room_activity", tool_id: @tool.id, active: true) do
          delete tool_room_activity_path(@tool, remaining: 2), as: :json
        end
        assert_response :no_content
      end

      test "destroy treats a missing or unparsable remaining count as an empty call" do
        assert_broadcast_on("notifications:#{@other_user.id}", type: "room_activity", tool_id: @tool.id, active: false) do
          delete tool_room_activity_path(@tool, remaining: "nonsense"), as: :json
        end
        assert_response :no_content
      end

      test "does not notify muted collaborators" do
        @tool.collaborators.find_by(user: @other_user).update!(muted_at: Time.current)

        assert_no_broadcasts("notifications:#{@other_user.id}") do
          post tool_room_activity_path(@tool), as: :json
        end
      end

      test "requires tool access" do
        sign_out
        sign_in_as users(:two)
        inaccessible_tool = Tool.create!(name: "Private room", tool_type: tool_types(:room), owner: users(:one))

        post tool_room_activity_path(inaccessible_tool), as: :json

        assert_response :forbidden
      end

      test "requires authentication" do
        sign_out

        post tool_room_activity_path(@tool), as: :json

        assert_response :unauthorized
      end
    end
  end
end

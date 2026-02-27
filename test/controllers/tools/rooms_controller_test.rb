# frozen_string_literal: true

require "test_helper"

module Tools
  class RoomsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_room)
    end

    test "show renders room" do
      get tool_room_path(@tool)
      assert_response :success
    end

    test "requires authentication" do
      sign_out
      get tool_room_path(@tool)
      assert_redirected_to new_session_path
    end
  end
end

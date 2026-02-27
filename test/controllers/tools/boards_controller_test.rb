# frozen_string_literal: true

require "test_helper"

module Tools
  class BoardsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:project_board)
    end

    test "show renders board with columns and cards" do
      get tool_board_path(@tool)

      assert_response :success
      assert_includes response.body, "To Do"
      assert_includes response.body, "In Progress"
      assert_includes response.body, "Done"
      assert_includes response.body, "First task"
    end

    test "new board tool automatically creates default board with columns" do
      new_tool = Tool.create!(name: "New Board", tool_type: tool_types(:board), owner: users(:one))

      assert_not_nil new_tool.board
      assert_equal 3, new_tool.board.columns.count

      get tool_board_path(new_tool)

      assert_response :success
    end

    test "show includes reorder mode when param present" do
      get tool_board_path(@tool, reorder: 1)

      assert_response :success
      assert_includes response.body, "reorder-mode"
    end

    test "requires authentication" do
      sign_out

      get tool_board_path(@tool)

      assert_redirected_to new_session_path
    end
  end
end

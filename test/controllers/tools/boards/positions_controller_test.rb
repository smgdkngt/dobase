# frozen_string_literal: true

require "test_helper"

module Tools
  module Boards
    class PositionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:project_board)
      end

      test "reorders columns" do
        todo = columns(:todo)
        in_progress = columns(:in_progress)
        done = columns(:done)

        # Verify initial positions
        assert_equal [ 0, 1, 2 ], [ todo.position, in_progress.position, done.position ]

        # Reverse order
        patch tool_board_positions_path(@tool),
              params: { column_ids: [ done.id, in_progress.id, todo.id ] },
              as: :json

        assert_response :success

        # Verify new positions
        assert_equal 2, todo.reload.position
        assert_equal 1, in_progress.reload.position
        assert_equal 0, done.reload.position
      end

      test "requires authentication" do
        sign_out

        patch tool_board_positions_path(@tool),
              params: { column_ids: [ columns(:todo).id ] },
              as: :json

        assert_redirected_to new_session_path
      end
    end
  end
end

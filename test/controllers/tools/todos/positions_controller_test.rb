# frozen_string_literal: true

require "test_helper"

module Tools
  module Todos
    class PositionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_todos)
      end

      test "reorders lists" do
        patch tool_todo_positions_path(@tool), params: { list_ids: [ todo_lists(:backlog).id, todo_lists(:main).id ] }, as: :json

        assert_response :success
        assert_equal [ 1, 0 ], todo_lists(:main, :backlog).map { |list| list.reload.position }
      end

      test "a reorder with no lists is a no-op, not a 500" do
        patch tool_todo_positions_path(@tool), params: {}, as: :json

        assert_response :success
        assert_equal [ 0, 1 ], todo_lists(:main, :backlog).map { |list| list.reload.position }
      end

      test "a list of another tool keeps its place" do
        patch tool_todo_positions_path(@tool), params: { list_ids: [ todo_lists(:main).id, todo_lists(:other_list).id ] }, as: :json

        assert_response :success
        assert_equal 0, todo_lists(:other_list).reload.position
      end
    end
  end
end

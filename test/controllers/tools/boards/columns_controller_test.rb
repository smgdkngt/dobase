# frozen_string_literal: true

require "test_helper"

module Tools
  module Boards
    class ColumnsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:project_board)
        @board = boards(:project)
      end

      test "create adds new column" do
        assert_difference "::Boards::Column.count", 1 do
          post tool_board_columns_path(@tool), params: { name: "New Column" }, as: :json
        end

        assert_response :success
        column = ::Boards::Column.last
        assert_equal "New Column", column.name
        assert_equal @board, column.board
      end

      test "create assigns next position" do
        initial_max = @board.columns.maximum(:position)

        post tool_board_columns_path(@tool), params: { name: "New Column" }, as: :json

        column = ::Boards::Column.last
        assert_equal initial_max + 1, column.position
      end

      test "update changes column name" do
        column = columns(:todo)

        patch tool_board_column_path(@tool, column), params: { name: "Updated Name" }, as: :json

        assert_response :success
        assert_equal "Updated Name", column.reload.name
      end

      test "destroy removes column" do
        column = columns(:done)

        assert_difference "::Boards::Column.count", -1 do
          delete tool_board_column_path(@tool, column)
        end

        assert_redirected_to tool_board_path(@tool)
      end

      test "destroy also removes column cards" do
        column = columns(:todo)
        card_count = column.cards.count

        assert_difference "::Boards::Card.count", -card_count do
          delete tool_board_column_path(@tool, column)
        end
      end

      test "requires authentication" do
        sign_out

        post tool_board_columns_path(@tool), params: { name: "New" }, as: :json

        assert_redirected_to new_session_path
      end
    end
  end
end

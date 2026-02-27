# frozen_string_literal: true

require "test_helper"

module Boards
  class BoardTest < ActiveSupport::TestCase
    test "belongs to a tool" do
      board = boards(:project)
      assert_equal tools(:project_board), board.tool
    end

    test "has many columns ordered by position" do
      board = boards(:project)
      assert_equal %w[To\ Do In\ Progress Done], board.columns.pluck(:name)
    end

    test "default board is created automatically when board tool is created" do
      tool = Tool.create!(name: "New Tool", tool_type: tool_types(:board), owner: users(:one))

      assert_not_nil tool.board
      assert_equal tool, tool.board.tool
      assert_equal 3, tool.board.columns.count
      assert_equal [ "To Do", "In Progress", "Done" ], tool.board.columns.pluck(:name)
      assert_equal [ 0, 1, 2 ], tool.board.columns.pluck(:position)
    end

    test "destroying board destroys columns" do
      board = boards(:project)
      column_ids = board.columns.pluck(:id)

      assert_difference "Boards::Column.count", -3 do
        board.destroy
      end

      assert_empty Boards::Column.where(id: column_ids)
    end
  end
end

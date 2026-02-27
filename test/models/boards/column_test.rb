# frozen_string_literal: true

require "test_helper"

module Boards
  class ColumnTest < ActiveSupport::TestCase
    test "belongs to a board" do
      column = columns(:todo)
      assert_equal boards(:project), column.board
    end

    test "has many cards ordered by position" do
      column = columns(:todo)
      assert_equal [ "First task", "Second task" ], column.cards.pluck(:title)
    end

    test "validates name presence" do
      column = Boards::Column.new(board: boards(:project), position: 10)
      assert_not column.valid?
      assert_includes column.errors[:name], "can't be blank"
    end

    test "destroying column destroys cards" do
      column = columns(:todo)
      card_count = column.cards.count

      assert_difference "Boards::Card.count", -card_count do
        column.destroy
      end
    end
  end
end

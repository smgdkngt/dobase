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

    test "collapsing is personal to one user" do
      column = columns(:todo)

      column.collapse_for(users(:one))

      assert column.collapsed_for?(users(:one))
      assert_not column.collapsed_for?(users(:two))
    end

    test "collapsing twice for the same user leaves one record" do
      column = columns(:todo)

      column.collapse_for(users(:one))
      column.collapse_for(users(:one))

      assert_equal 1, column.collapses.count
    end

    test "expanding drops only that user's collapse" do
      column = columns(:todo)
      column.collapse_for(users(:one))
      column.collapse_for(users(:two))

      column.expand_for(users(:one))

      assert_not column.collapsed_for?(users(:one))
      assert column.collapsed_for?(users(:two))
    end

    test "destroying column destroys its collapses" do
      column = columns(:todo)
      column.collapse_for(users(:one))

      assert_difference "Boards::ColumnCollapse.count", -1 do
        column.destroy
      end
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

# frozen_string_literal: true

require "test_helper"

module Columns
  class PositionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @column = columns(:todo)
    end

    test "reorders cards within the same column" do
      first_card = cards(:first_task)
      second_card = cards(:second_task)

      # Verify initial positions
      assert_equal 0, first_card.position
      assert_equal 1, second_card.position

      # Swap positions
      patch column_positions_path(@column),
            params: { card_ids: [ second_card.id, first_card.id ] },
            as: :json

      assert_response :success

      # Verify positions updated
      assert_equal 1, first_card.reload.position
      assert_equal 0, second_card.reload.position
    end

    test "moves card from another column" do
      card_from_in_progress = cards(:third_task)
      first_card = cards(:first_task)

      # Card starts in "In Progress" column
      assert_equal columns(:in_progress), card_from_in_progress.column

      # Move to "To Do" column at position 0
      patch column_positions_path(@column),
            params: { card_ids: [ card_from_in_progress.id, first_card.id, cards(:second_task).id ] },
            as: :json

      assert_response :success

      # Card is now in "To Do" column
      card_from_in_progress.reload
      assert_equal @column, card_from_in_progress.column
      assert_equal 0, card_from_in_progress.position
    end

    test "requires authentication" do
      sign_out

      patch column_positions_path(@column),
            params: { card_ids: [ cards(:first_task).id ] },
            as: :json

      assert_response :unauthorized
    end

    test "cannot pull cards from a board the user has no access to" do
      sign_in_as users(:two)
      own_column = boards(:shared).columns.create!(name: "Mine", position: 0)
      own_card = own_column.cards.create!(title: "My card", position: 3)
      foreign_card = cards(:first_task)
      foreign_card.update!(assigned_user: users(:one))

      assert_no_difference -> { users(:one).notifications.count } do
        patch column_positions_path(own_column),
              params: { card_ids: [ foreign_card.id, own_card.id ] },
              as: :json
      end

      assert_response :success
      assert_equal columns(:todo), foreign_card.reload.column
      assert_equal 0, foreign_card.position
      assert_equal 0, own_card.reload.position
    end
  end
end

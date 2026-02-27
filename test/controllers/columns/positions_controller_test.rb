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

      assert_redirected_to new_session_path
    end
  end
end

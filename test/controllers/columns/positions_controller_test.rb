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

    test "reordering with a filter on keeps the hidden cards in place" do
      first, second = cards(:first_task), cards(:second_task)
      third = @column.cards.create!(title: "Third in To Do", position: 2)

      # The filter hides the second card: only the first and third were shown
      patch column_positions_path(@column), params: { card_ids: [ third.id, first.id ] }, as: :json

      assert_response :success
      assert_equal [ third, first, second ], @column.cards.order(:position).to_a
      assert_equal [ 0, 1, 2 ], @column.cards.order(:position).pluck(:position)
    end

    test "a card's assignee who has left the board isn't told it moved" do
      card = cards(:third_task)
      card.update_column(:assigned_user_id, users(:two).id)

      assert_no_difference -> { users(:two).notifications.count } do
        patch column_positions_path(@column), params: { card_ids: [ card.id, cards(:first_task).id ] }, as: :json
      end

      assert_response :success
      assert_equal @column, card.reload.column
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

    test "a card the request doesn't list never changes column" do
      board = @column.board
      from, to = board.columns.order(:position).first(2)
      staying = from.cards.create!(title: "Staying", position: 0)
      travelling = to.cards.create!(title: "Travelling", position: 0)

      # What a reorder of `from` sees when the card was dragged to `to` while the
      # request was on its way: the order it works out still holds the card that left.
      original = KeepHiddenInPlace.method(:call)
      KeepHiddenInPlace.define_singleton_method(:call) { |_current, requested| requested + [ travelling.id ] }
      begin
        patch column_positions_path(from), params: { card_ids: [ staying.id ] }, as: :json
      ensure
        KeepHiddenInPlace.define_singleton_method(:call, original)
      end

      assert_response :success
      assert_equal to.id, travelling.reload.column_id
      assert_equal 0, staying.reload.position
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Columns
  class CardsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @column = columns(:todo)
      @tool = tools(:project_board)
    end

    test "create adds new card to column" do
      assert_difference "Boards::Card.count", 1 do
        post column_cards_path(@column), params: { title: "New Card" }
      end

      assert_redirected_to tool_board_path(@tool)
      card = Boards::Card.last
      assert_equal "New Card", card.title
      assert_equal @column, card.column
    end

    test "create assigns next position" do
      initial_max = @column.cards.maximum(:position)

      post column_cards_path(@column), params: { title: "New Card" }

      card = Boards::Card.last
      assert_equal initial_max + 1, card.position
    end

    test "requires authentication" do
      sign_out

      post column_cards_path(@column), params: { title: "New Card" }

      assert_redirected_to new_session_path
    end
  end
end

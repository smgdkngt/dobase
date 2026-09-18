# frozen_string_literal: true

require "test_helper"

class FrameNotFoundTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "a frame whose record is gone says so inside the frame" do
    tool = tools(:project_board)
    card = tool.board.columns.first.cards.create!(title: "Gone in a moment", position: 1)
    card.destroy!

    get tool_board_card_path(tool, card), headers: { "Turbo-Frame" => "card-detail-content" }

    assert_response :not_found
    assert_select "turbo-frame#card-detail-content", text: /no longer exists/
  end

  test "a normal request still goes home with an alert" do
    tool = tools(:project_board)
    card = tool.board.columns.first.cards.create!(title: "Gone in a moment", position: 1)
    card.destroy!

    get tool_board_card_path(tool, card)

    assert_redirected_to root_path
    assert_equal "That item no longer exists.", flash[:alert]
  end
end

# frozen_string_literal: true

require "test_helper"

module Tools
  module Boards
    class CardsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @card = cards(:first_task)
        @tool = tools(:project_board)
      end

      test "show renders card detail" do
        get tool_board_card_path(@tool, @card)

        assert_response :success
        assert_includes response.body, @card.title
      end

      test "update changes card title" do
        patch tool_board_card_path(@tool, @card), params: { card: { title: "Updated Title" } }, as: :json

        assert_response :success
        assert_equal "Updated Title", @card.reload.title
      end

      test "update changes card description" do
        patch tool_board_card_path(@tool, @card), params: { card: { description: "New description" } }, as: :json

        assert_response :success
        assert_equal "New description", @card.reload.description.to_plain_text
      end

      test "update changes card color" do
        patch tool_board_card_path(@tool, @card), params: { card: { color: "red" } }, as: :json

        assert_response :success
        assert_equal "red", @card.reload.color
      end

      test "update clears card color" do
        @card.update!(color: "blue")

        patch tool_board_card_path(@tool, @card), params: { card: { color: "" } }, as: :json

        assert_response :success
        assert_empty @card.reload.color.to_s
      end

      test "update changes due date" do
        due_date = Date.tomorrow

        patch tool_board_card_path(@tool, @card), params: { card: { due_date: due_date } }, as: :json

        assert_response :success
        assert_equal due_date, @card.reload.due_date
      end

      test "update assigns user" do
        user = users(:one)

        patch tool_board_card_path(@tool, @card), params: { card: { assigned_user_id: user.id } }, as: :json

        assert_response :success
        assert_equal user, @card.reload.assigned_user
      end

      test "update unassigns user" do
        @card.update!(assigned_user: users(:one))

        patch tool_board_card_path(@tool, @card), params: { card: { assigned_user_id: nil } }, as: :json

        assert_response :success
        assert_nil @card.reload.assigned_user
      end

      test "update with invalid data returns errors" do
        patch tool_board_card_path(@tool, @card), params: { card: { title: "" } }, as: :json

        assert_response :unprocessable_entity
      end

      test "destroy removes card" do
        assert_difference "::Boards::Card.count", -1 do
          delete tool_board_card_path(@tool, @card), as: :json
        end

        assert_response :success
      end

      test "update assigning another user sends notification" do
        user_two = users(:two)
        @tool.collaborators.find_or_create_by!(user: user_two, role: "collaborator")

        assert_difference -> { user_two.notifications.count }, 1 do
          patch tool_board_card_path(@tool, @card), params: { card: { assigned_user_id: user_two.id } }, as: :json
        end

        assert_response :success
      end

      test "update self-assigning does not send notification" do
        assert_no_difference -> { users(:one).notifications.count } do
          patch tool_board_card_path(@tool, @card), params: { card: { assigned_user_id: users(:one).id } }, as: :json
        end

        assert_response :success
      end

      test "requires authentication" do
        sign_out

        get tool_board_card_path(@tool, @card)
        assert_redirected_to new_session_path
      end
    end
  end
end

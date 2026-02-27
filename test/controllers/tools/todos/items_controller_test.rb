# frozen_string_literal: true

require "test_helper"

module Tools
  module Todos
    class ItemsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @item = todo_items(:pending_one)
        @tool = tools(:my_todos)
      end

      test "show renders item detail" do
        get tool_todo_item_path(@tool, @item)

        assert_response :success
        assert_includes response.body, @item.title
      end

      test "update changes item title" do
        patch tool_todo_item_path(@tool, @item), params: { item: { title: "Updated Title" } }, as: :json

        assert_response :success
        assert_equal "Updated Title", @item.reload.title
      end

      test "update changes item description" do
        patch tool_todo_item_path(@tool, @item), params: { item: { description: "New desc" } }, as: :json

        assert_response :success
        assert_equal "New desc", @item.reload.description.to_plain_text
      end

      test "update changes due date" do
        due_date = Date.tomorrow

        patch tool_todo_item_path(@tool, @item), params: { item: { due_date: due_date } }, as: :json

        assert_response :success
        assert_equal due_date, @item.reload.due_date
      end

      test "update assigns user" do
        user = users(:one)

        patch tool_todo_item_path(@tool, @item), params: { item: { assigned_user_id: user.id } }, as: :json

        assert_response :success
        assert_equal user, @item.reload.assigned_user
      end

      test "update with invalid data returns errors" do
        patch tool_todo_item_path(@tool, @item), params: { item: { title: "" } }, as: :json

        assert_response :unprocessable_entity
      end

      test "destroy removes item" do
        assert_difference "::Todos::Item.count", -1 do
          delete tool_todo_item_path(@tool, @item), as: :json
        end

        assert_response :success
      end

      test "update assigning another user sends notification" do
        user_two = users(:two)
        @tool.collaborators.find_or_create_by!(user: user_two, role: "collaborator")

        assert_difference -> { user_two.notifications.count }, 1 do
          patch tool_todo_item_path(@tool, @item), params: { item: { assigned_user_id: user_two.id } }, as: :json
        end

        assert_response :success
      end

      test "update self-assigning does not send notification" do
        assert_no_difference -> { users(:one).notifications.count } do
          patch tool_todo_item_path(@tool, @item), params: { item: { assigned_user_id: users(:one).id } }, as: :json
        end

        assert_response :success
      end

      test "requires authentication" do
        sign_out

        get tool_todo_item_path(@tool, @item)
        assert_redirected_to new_session_path
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Tools
  module Todos
    class ListsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_todos)
      end

      test "create adds new list" do
        assert_difference "::Todos::List.count", 1 do
          post tool_todo_lists_path(@tool), params: { title: "New List" }, as: :json
        end

        assert_response :success
        list = ::Todos::List.last
        assert_equal "New List", list.title
        assert_equal @tool, list.tool
      end

      test "create assigns next position" do
        initial_max = @tool.todo_lists.maximum(:position)

        post tool_todo_lists_path(@tool), params: { title: "New List" }, as: :json

        list = ::Todos::List.last
        assert_equal initial_max + 1, list.position
      end

      test "update changes list title" do
        list = todo_lists(:main)

        patch tool_todo_list_path(@tool, list), params: { title: "Updated Name" }, as: :json

        assert_response :success
        assert_equal "Updated Name", list.reload.title
      end

      test "destroy removes list" do
        list = todo_lists(:backlog)

        assert_difference "::Todos::List.count", -1 do
          delete tool_todo_list_path(@tool, list)
        end

        assert_redirected_to tool_todo_path(@tool)
      end

      test "destroy also removes list items" do
        list = todo_lists(:main)
        item_count = list.items.count

        assert_difference "::Todos::Item.count", -item_count do
          delete tool_todo_list_path(@tool, list)
        end
      end

      test "requires authentication" do
        sign_out

        post tool_todo_lists_path(@tool), params: { title: "New" }, as: :json

        assert_redirected_to new_session_path
      end
    end
  end
end

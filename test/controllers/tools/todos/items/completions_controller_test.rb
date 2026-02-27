# frozen_string_literal: true

require "test_helper"

module Tools
  module Todos
    module Items
      class CompletionsControllerTest < ActionDispatch::IntegrationTest
        setup do
          sign_in_as users(:one)
          @tool = tools(:my_todos)
          @item = todo_items(:pending_one)
        end

        test "create marks item as completed" do
          assert_nil @item.completed_at

          post tool_todo_item_completion_path(@tool, @item), as: :json

          assert_response :success
          assert_not_nil @item.reload.completed_at
        end

        test "destroy marks item as not completed" do
          completed_item = todo_items(:recently_completed)

          delete tool_todo_item_completion_path(@tool, completed_item), as: :json

          assert_response :success
          assert_nil completed_item.reload.completed_at
        end

        test "requires authentication" do
          sign_out

          post tool_todo_item_completion_path(@tool, @item), as: :json

          assert_redirected_to new_session_path
        end
      end
    end
  end
end

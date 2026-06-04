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

        test "completing a recurring item spawns the next instance in the same list" do
          @item.update!(recurrence_rule: "daily", due_date: Date.current)

          assert_difference -> { @item.list.items.count }, 1 do
            post tool_todo_item_completion_path(@tool, @item), as: :json
          end

          new_item = @item.list.items.pending.where(recurrence_rule: "daily").order(created_at: :desc).first
          assert_equal @item.title, new_item.title
          assert_equal Date.current + 1.day, new_item.due_date
        end

        test "completing a non-recurring item does not spawn a copy" do
          assert_nil @item.recurrence_rule

          assert_no_difference -> { @item.list.items.count } do
            post tool_todo_item_completion_path(@tool, @item), as: :json
          end
        end
      end
    end
  end
end

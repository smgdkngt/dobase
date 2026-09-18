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

        test "create records who completed the item" do
          post tool_todo_item_completion_path(@tool, @item), as: :json

          assert_equal users(:one), @item.reload.updated_by
        end

        test "destroy records who reopened the item" do
          completed_item = todo_items(:recently_completed)

          delete tool_todo_item_completion_path(@tool, completed_item), as: :json

          assert_equal users(:one), completed_item.reload.updated_by
        end

        test "requires authentication" do
          sign_out

          post tool_todo_item_completion_path(@tool, @item), as: :json

          assert_response :unauthorized
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

        test "putting a repeating item back on the list takes its untouched copy with it" do
          @item.update!(recurrence_rule: "daily", due_date: Date.current)
          post tool_todo_item_completion_path(@tool, @item), as: :json
          copy = @item.reload.spawned_copy
          assert copy.present?

          assert_difference -> { @item.list.items.count }, -1 do
            delete tool_todo_item_completion_path(@tool, @item), as: :json
          end

          assert_nil @item.reload.completed_at
          assert_not ::Todos::Item.exists?(copy.id)
        end

        test "a copy someone has commented on stays when the item is put back" do
          @item.update!(recurrence_rule: "daily", due_date: Date.current)
          post tool_todo_item_completion_path(@tool, @item), as: :json
          copy = @item.reload.spawned_copy
          copy.comments.create!(user: users(:one), body: "Started on this")

          assert_no_difference -> { @item.list.items.count } do
            delete tool_todo_item_completion_path(@tool, @item), as: :json
          end

          assert ::Todos::Item.exists?(copy.id)
        end

        test "a copy already ticked off stays when the item is put back" do
          @item.update!(recurrence_rule: "daily", due_date: Date.current)
          post tool_todo_item_completion_path(@tool, @item), as: :json
          copy = @item.reload.spawned_copy
          copy.update!(completed_at: Time.current)

          delete tool_todo_item_completion_path(@tool, @item), as: :json

          assert ::Todos::Item.exists?(copy.id)
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

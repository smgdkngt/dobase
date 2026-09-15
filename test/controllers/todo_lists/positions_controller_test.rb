# frozen_string_literal: true

require "test_helper"

module TodoLists
  class PositionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
    end

    test "reorders items and moves them between the tool's lists" do
      patch todo_list_positions_path(todo_lists(:backlog)),
            params: { item_ids: [ todo_items(:pending_two).id, todo_items(:pending_one).id ] },
            as: :json

      assert_response :success
      assert_equal todo_lists(:backlog), todo_items(:pending_two).reload.list
      assert_equal 0, todo_items(:pending_two).position
      assert_equal todo_lists(:backlog), todo_items(:pending_one).reload.list
      assert_equal 1, todo_items(:pending_one).position
    end

    test "cannot pull items from a tool the user has no access to" do
      foreign_item = todo_items(:other_item)

      patch todo_list_positions_path(todo_lists(:main)),
            params: { item_ids: [ foreign_item.id, todo_items(:pending_one).id ] },
            as: :json

      assert_response :success
      assert_equal todo_lists(:other_list), foreign_item.reload.list
      assert_equal todo_lists(:main), todo_items(:pending_one).reload.list
      assert_equal 0, todo_items(:pending_one).position
    end

    test "requires access to the target list" do
      patch todo_list_positions_path(todo_lists(:other_list)),
            params: { item_ids: [ todo_items(:pending_one).id ] },
            as: :json

      assert_response :forbidden
      assert_equal todo_lists(:main), todo_items(:pending_one).reload.list
    end
  end
end

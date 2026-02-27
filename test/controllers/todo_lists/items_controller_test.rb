# frozen_string_literal: true

require "test_helper"

module TodoLists
  class ItemsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @list = todo_lists(:main)
      @tool = tools(:my_todos)
    end

    test "create adds item to list" do
      assert_difference "::Todos::Item.count", 1 do
        post todo_list_items_path(@list), params: { title: "New item" }
      end

      assert_redirected_to tool_todo_path(@tool)

      item = ::Todos::Item.last
      assert_equal "New item", item.title
      assert_equal @list, item.list
    end

    test "create assigns next position" do
      initial_max = @list.items.maximum(:position)

      post todo_list_items_path(@list), params: { title: "New item" }

      item = ::Todos::Item.last
      assert_equal initial_max + 1, item.position
    end

    test "requires authentication" do
      sign_out

      post todo_list_items_path(@list), params: { title: "New" }

      assert_redirected_to new_session_path
    end
  end
end

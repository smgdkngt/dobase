# frozen_string_literal: true

require "test_helper"

module Tools
  class TodosControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_todos)
    end

    test "show renders todo lists and items" do
      get tool_todo_path(@tool)

      assert_response :success
      assert_includes response.body, "To Do"
      assert_includes response.body, "Backlog"
      assert_includes response.body, "Buy groceries"
    end

    test "new todos tool automatically creates default list" do
      new_tool = Tool.create!(name: "New Todos", tool_type: tool_types(:todos), owner: users(:one))

      assert_equal 1, new_tool.todo_lists.count

      get tool_todo_path(new_tool)

      assert_response :success
    end

    test "requires authentication" do
      sign_out

      get tool_todo_path(@tool)

      assert_redirected_to new_session_path
    end
  end
end

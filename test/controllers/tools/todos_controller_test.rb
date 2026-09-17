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

    test "assignee=me shows only items assigned to current_user" do
      @tool.collaborators.create!(user: users(:two), role: "collaborator")
      todo_items(:pending_one).update!(assigned_user: users(:one))
      todo_items(:pending_two).update!(assigned_user: users(:two))

      get tool_todo_path(@tool, assignee: "me")

      assert_response :success
      assert_includes response.body, todo_items(:pending_one).title
      refute_includes response.body, todo_items(:pending_two).title
    end

    test "assignee=unassigned shows only items without an assignee" do
      todo_items(:pending_one).update!(assigned_user: users(:one))

      get tool_todo_path(@tool, assignee: "unassigned")

      assert_response :success
      refute_includes response.body, todo_items(:pending_one).title
      assert_includes response.body, todo_items(:pending_two).title
    end

    test "show runs the same number of queries however many items the lists have" do
      list = @tool.todo_lists.first
      add_items = -> do
        5.times do |index|
          item = list.items.create!(title: "More #{index}", position: 100 + index, assigned_user: users(:one), description: "<p>Notes</p>")
          item.comments.create!(user: users(:one), body: "A comment")
        end
        list.items.create!(title: "Done today", position: 200, completed_at: 1.hour.ago)
        list.items.create!(title: "Done last week", position: 201, completed_at: 1.week.ago)
      end

      assert_queries_independent_of(add_items) { get tool_todo_path(@tool) }
    end
  end
end

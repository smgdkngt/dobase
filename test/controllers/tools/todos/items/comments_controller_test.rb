# frozen_string_literal: true

require "test_helper"

module Tools
  module Todos
    module Items
      class CommentsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @tool = tools(:my_todos)
          @item = todo_items(:pending_one)
          @collaborator = Collaborator.create!(tool: @tool, user: users(:two), role: "collaborator")
        end

        test "create adds a comment" do
          sign_in_as users(:one)

          assert_difference "::Todos::Comment.count", 1 do
            post tool_todo_item_comments_path(@tool, @item), params: { body: "<p>Hello</p>" }, as: :json
          end

          assert_response :created
        end

        test "the item page offers a delete control for your own comment" do
          sign_in_as users(:one)
          comment = todo_comments(:first_comment)

          get tool_todo_item_path(@tool, @item)

          assert_select "a[href=?][data-turbo-method=delete]", tool_todo_item_comment_path(@tool, @item, comment)
        end

        test "an owner can delete somebody else's comment from the page" do
          sign_in_as users(:one)
          comment = @item.comments.create!(user: users(:two), body: "<p>Theirs</p>")

          get tool_todo_item_path(@tool, @item)

          assert_select "a[href=?][data-turbo-method=delete]", tool_todo_item_comment_path(@tool, @item, comment)
        end

        test "a collaborator gets no delete control on somebody else's comment" do
          sign_in_as users(:two)
          comment = todo_comments(:first_comment)

          get tool_todo_item_path(@tool, @item)

          assert_select "a[href=?]", tool_todo_item_comment_path(@tool, @item, comment), count: 0
        end

        test "destroy removes your own comment" do
          sign_in_as users(:one)
          comment = todo_comments(:first_comment)

          assert_difference "::Todos::Comment.count", -1 do
            delete tool_todo_item_comment_path(@tool, @item, comment), as: :json
          end

          assert_response :no_content
        end

        test "destroy refuses somebody else's comment" do
          sign_in_as users(:two)
          comment = todo_comments(:first_comment)

          assert_no_difference "::Todos::Comment.count" do
            delete tool_todo_item_comment_path(@tool, @item, comment), as: :json
          end

          assert_response :forbidden
        end
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Tools
  class DocsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_docs)
    end

    test "show renders documents index" do
      get tool_docs_path(@tool)

      assert_response :success
      assert_includes response.body, "Meeting Notes"
      assert_includes response.body, "Project Plan"
    end

    test "show defaults to grid view" do
      get tool_docs_path(@tool)

      assert_response :success
      assert_includes response.body, "grid"
    end

    test "show can switch to list view" do
      get tool_docs_path(@tool, view: "list")

      assert_response :success
    end

    test "requires authentication" do
      sign_out

      get tool_docs_path(@tool)

      assert_redirected_to new_session_path
    end
  end
end

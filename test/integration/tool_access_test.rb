# frozen_string_literal: true

require "test_helper"

class ToolAccessTest < ActionDispatch::IntegrationTest
  TOOL_PATHS = {
    project_board: ->(tool) { "/tools/#{tool.id}/board" },
    my_docs:       ->(tool) { "/tools/#{tool.id}/docs" },
    my_calendar:   ->(tool) { "/tools/#{tool.id}/calendar" },
    my_files:      ->(tool) { "/tools/#{tool.id}/files" },
    my_mail:       ->(tool) { "/tools/#{tool.id}/mails" },
    my_room:       ->(tool) { "/tools/#{tool.id}/room" },
    my_todos:      ->(tool) { "/tools/#{tool.id}/todo" }
  }.freeze

  TOOL_PATHS.each do |fixture_name, path_for|
    test "outsider is denied access to #{fixture_name}" do
      sign_in_as users(:two)

      get path_for.call(tools(fixture_name))

      assert_redirected_to root_path
      assert_equal "You don't have access to this tool.", flash[:alert]
    end
  end

  test "collaborator can access the shared board" do
    sign_in_as users(:two)

    get "/tools/#{tools(:shared_board).id}/board"

    assert_response :success
  end

  test "collaborator cannot destroy the tool" do
    sign_in_as users(:two)
    shared = tools(:shared_board)

    delete tool_path(shared)

    assert_redirected_to root_path
    assert_equal "Only the owner can perform this action.", flash[:alert]
    assert Tool.exists?(shared.id)
  end

  test "outsider cannot destroy the tool" do
    sign_in_as users(:two)
    private_tool = tools(:my_files)

    delete tool_path(private_tool)

    assert_redirected_to root_path
    assert Tool.exists?(private_tool.id)
  end

  test "unauthenticated request is redirected to login" do
    get "/tools/#{tools(:project_board).id}/board"

    assert_redirected_to new_session_path
  end
end

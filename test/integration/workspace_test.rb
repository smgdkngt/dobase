# frozen_string_literal: true

require "test_helper"

# The tiling workspace (WorkspacesController, workspace_controller.js): the server
# draws the room, the browser keeps the tiles.
class WorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "the workspace is a room for tiles, with the sidebar as its menu and no pane beside" do
    get workspace_path

    assert_response :success
    assert_select "html[data-workspace]"
    assert_select "[data-controller~='workspace'] #workspace-tiles[data-turbo-permanent]"
    assert_select "aside.sidebar"
    assert_select "template#side-pane-template", count: 0
    assert_select "form[action='#{workspace_path}'][data-turbo='false'] button", text: /Leave the workspace/
  end

  test "any other page offers the workspace from the menu" do
    get tool_files_path(tools(:my_files))

    assert_select "html[data-workspace]", count: 0
    assert_select "#sidebar-add-menu a[href='#{workspace_path}']", text: /Tiling workspace/
  end

  test "a browser that works in the workspace comes back to it, until it leaves" do
    @user.update_column(:last_visited_path, tool_files_path(tools(:my_files)))

    get workspace_path
    get root_path
    assert_redirected_to workspace_path

    delete workspace_path
    assert_redirected_to root_path

    get root_path
    assert_redirected_to tool_files_path(tools(:my_files))
  end

  test "a tile never holds the workspace itself" do
    get workspace_path, headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_redirected_to root_path
  end

  test "a tile sent to the dashboard stays there, also from a browser that works in the workspace" do
    get workspace_path

    get root_path, headers: { "X-Side-Pane" => "1" }

    assert_response :success
  end
end

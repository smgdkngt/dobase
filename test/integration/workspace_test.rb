# frozen_string_literal: true

require "test_helper"

# The tiling workspace (WorkspacesController, workspace_controller.js): the server
# draws the room, the browser keeps the tiles. It is how a wide window works unless
# the window is a phone's.
class WorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @files = tools(:my_files)
    sign_in_as @user
  end

  test "the workspace is a room for tiles, with the sidebar as its menu" do
    get workspace_path

    assert_response :success
    assert_select "body[data-workspace]"
    assert_select "[data-controller~='workspace'] #workspace-tiles[data-turbo-permanent]"
    assert_select "aside.sidebar"
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    # There is no way out of it: this is how a wide window works
    assert_select "#sidebar-user-menu form[action='#{workspace_path}']", count: 0
  end

  test "an empty workspace opens with the tool you were last on, or your first one" do
    get workspace_path
    first = @user.ungrouped_tools.first || @user.accessible_tools.first
    assert_select "[data-controller~='workspace'][data-workspace-start-value='#{tool_path(first)}']"

    @user.update_column(:last_visited_path, tool_files_path(@files))
    get workspace_path
    assert_select "[data-controller~='workspace'][data-workspace-start-value='#{tool_files_path(@files)}']"

    @user.update_column(:last_visited_path, "/tools/#{tools(:other_calendar).id}/calendar")
    get workspace_path
    assert_select "[data-controller~='workspace'][data-workspace-start-value='#{tool_path(first)}']"
  end

  test "someone without tools is welcomed in the workspace as anywhere" do
    user = users(:two)
    Collaborator.where(user: user).delete_all
    sign_in_as user

    get workspace_path

    assert_select "[data-workspace-target='empty']", text: /Create your first tool/
  end

  test "the start page is the workspace" do
    @user.update_column(:last_visited_path, tool_files_path(@files))

    get root_path
    assert_redirected_to workspace_path
  end

  test "there is no asking for one tool at a time" do
    delete "/workspace"

    assert_response :not_found
  end

  test "a phone, and a window the workspace found too narrow, get one tool" do
    @user.update_column(:last_visited_path, tool_files_path(@files))

    get root_path, headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 26_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Mobile/15E148 Safari/604.1" }
    assert_redirected_to tool_files_path(@files)

    get root_path(one: 1)
    assert_redirected_to tool_files_path(@files)
  end

  test "a tool opened by its address sends a wide window to the workspace with it" do
    get tool_files_path(@files, view: "list")

    assert_response :success
    assert_select "head script[src*='workspace_gate'][data-wide='#{workspace_path(open: tool_files_path(@files, view: "list"))}']"
  end

  test "the workspace hands a narrow window over to one tool" do
    get workspace_path

    assert_select "head script[src*='workspace_gate'][data-narrow='#{root_path(one: 1)}'][data-storage-key='dobase:workspace:#{@user.id}'][data-tools~='#{@files.id}']"
  end

  test "a tile never holds the workspace itself" do
    get workspace_path, headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_redirected_to root_path
  end
end

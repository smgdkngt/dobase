# frozen_string_literal: true

require "test_helper"

# A tile in the workspace is a tool's page in a frame, drawn without the sidebar
# (ApplicationController#tile?, workspace_controller.js).
class TilePageTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
  end

  test "a page the browser loads into a frame is the tool alone" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_response :success
    assert_select "html[data-in-tile]"
    assert_select "[data-controller~='tile-page'] main#main-content"
    assert_select "aside.sidebar", count: 0
    assert_select ".mobile-bottom-bar", count: 0
    assert_select "[data-controller~='notifications']", count: 0
    # It keeps its own command palette and shortcuts, with the workspace's keys among them
    assert_select "dialog[data-controller~='command-palette']"
    assert_select "dialog h3", text: "Workspace"
    # And goes from page to page without the cross-fade Turbo would wait for
    assert_select "meta[name='view-transition']", count: 0
  end

  test "a page Turbo asks for from inside the frame is the tool alone too" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "X-Tile" => "1" }

    assert_select "html[data-in-tile]"
    assert_select "aside.sidebar", count: 0
  end

  test "a tile never sends itself to the workspace" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_select "script[src*='workspace_gate']", count: 0
  end

  test "the app can be framed by itself and by nobody else" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors 'self'"
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
  end

  test "a tool in a tile is seen, and with several open none of them is where you were last" do
    sign_in_as @user
    get tool_board_path(tools(:project_board))
    Collaborator.where(user: @user, tool: @tool).update_all(last_seen_at: nil)

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_equal tool_board_path(tools(:project_board)), @user.reload.last_visited_path
    assert_not_nil Collaborator.find_by(user: @user, tool: @tool).last_seen_at
  end

  test "a tile sent to the dashboard stays there instead of opening a tool or the workspace" do
    sign_in_as @user
    @user.update_column(:last_visited_path, tool_files_path(@tool))

    get root_path, headers: { "X-Tile" => "1" }

    assert_response :success
  end

  test "signing in again returns to the workspace, not to a page that was a tile in it" do
    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_url
  end
end

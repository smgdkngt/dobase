# frozen_string_literal: true

require "test_helper"

# A tool shown beside another one is a page in a frame, drawn without the sidebar
# (ApplicationController#side_pane?, side_pane_controller.js).
class SidePaneTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
  end

  test "a page of its own has the sidebar, the pane to put beside it and a button per tool" do
    sign_in_as @user

    get tool_files_path(@tool)

    assert_response :success
    assert_select "html[data-in-side-pane]", count: 0
    assert_select "meta[name='view-transition']"
    assert_select "aside.sidebar"
    assert_select "template#side-pane-template"
    assert_select "button[data-side-pane-toggle][data-tool-id='#{@tool.id}'][data-url='#{tool_path(@tool)}']"
  end

  test "a page the browser loads into a frame is the tool alone" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_response :success
    assert_select "html[data-in-side-pane]"
    assert_select "[data-controller~='side-pane-page'] main#main-content"
    assert_select "aside.sidebar", count: 0
    assert_select ".mobile-bottom-bar", count: 0
    assert_select "template#side-pane-template", count: 0
    assert_select "[data-controller~='notifications']", count: 0
    # It keeps its own command palette and shortcuts
    assert_select "dialog[data-controller~='command-palette']"
    # And goes from page to page without the cross-fade Turbo would wait for
    assert_select "meta[name='view-transition']", count: 0
  end

  test "the app can be framed by itself and by nobody else" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors 'self'"
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
  end

  test "a page Turbo asks for from inside the frame is the tool alone too" do
    sign_in_as @user

    get tool_files_path(@tool), headers: { "X-Side-Pane" => "1" }

    assert_select "html[data-in-side-pane]"
    assert_select "aside.sidebar", count: 0
  end

  test "the tool beside is seen, and isn't where the dashboard returns to" do
    sign_in_as @user
    get tool_board_path(tools(:project_board))
    Collaborator.where(user: @user, tool: @tool).update_all(last_seen_at: nil)

    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }

    assert_equal tool_board_path(tools(:project_board)), @user.reload.last_visited_path
    assert_not_nil Collaborator.find_by(user: @user, tool: @tool).last_seen_at
  end

  test "a pane sent to the dashboard stays there instead of opening the tool you were on" do
    sign_in_as @user
    @user.update_column(:last_visited_path, tool_files_path(@tool))

    get root_path, headers: { "X-Side-Pane" => "1" }

    assert_response :success
  end

  test "signing in again returns to the page itself, not to the one that was beside it" do
    get tool_files_path(@tool), headers: { "Sec-Fetch-Dest" => "iframe" }
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_url
  end
end

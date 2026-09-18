# frozen_string_literal: true

require "test_helper"

class ToolsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = api_headers(@user)
  end

  test "index lists accessible tools" do
    get tools_path, headers: @headers

    assert_response :success
    board = response.parsed_body.find { |tool| tool["id"] == tools(:project_board).id }
    assert_equal "Project Board", board["name"]
    assert_equal "boards", board["type"]
    assert_equal tool_url(tools(:project_board)), board["url"]
    assert_includes [ true, false ], board["unread"]
    assert_not response.parsed_body.any? { |tool| tool["id"] == tools(:other_calendar).id }
  end

  test "show includes the caller's role and the collaborators" do
    get tool_path(tools(:project_board)), headers: @headers

    assert_response :success
    assert_equal "owner", response.parsed_body["role"]
    assert_equal [ @user.email_address ], response.parsed_body["collaborators"].map { |user| user["email_address"] }
  end

  test "show refuses tools the user can't access" do
    get tool_path(tools(:other_calendar)), headers: @headers

    assert_response :forbidden
    assert_equal "You don't have access to this tool.", response.parsed_body["error"]
  end

  test "show returns 404 for unknown tools" do
    get tool_path(id: 0), headers: @headers

    assert_response :not_found
    assert_equal "Not found", response.parsed_body["error"]
  end

  test "create builds a tool from a type slug" do
    assert_difference -> { Tool.count }, 1 do
      post tools_path, params: { tool: { name: "Launch plan", tool_type: "todos" } }, headers: @headers, as: :json
    end

    assert_response :created
    assert_equal "todos", response.parsed_body["type"]
    assert_equal "owner", response.parsed_body["role"]
    assert Tool.find(response.parsed_body["id"]).todo_lists.any?
  end

  test "create with an unknown type returns validation errors" do
    assert_no_difference -> { Tool.count } do
      post tools_path, params: { tool: { name: "Nope", tool_type: "spreadsheets" } }, headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Tool type must exist"
  end

  test "update renames the tool" do
    patch tool_path(tools(:project_board)), params: { tool: { name: "Roadmap" } }, headers: @headers, as: :json

    assert_response :success
    assert_equal "Roadmap", response.parsed_body["name"]
    assert_equal "Roadmap", tools(:project_board).reload.name
  end

  test "update can't turn a board into another kind of tool" do
    board = tools(:project_board)

    patch tool_path(board), params: { tool: { name: "Roadmap", tool_type: "todos" } }, headers: @headers, as: :json

    assert_response :success
    assert_equal "boards", board.reload.tool_type.slug
  end
end

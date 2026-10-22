# frozen_string_literal: true

require "test_helper"

class Mcp::ApiTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @token = @user.access_tokens.create!(name: "Claude", permission: "write")
    @api = Mcp::Api.new(token: @token.token, host: "app.example.com", https: true)
  end

  test "asks the JSON API as the token's owner" do
    tools = @api.get("/tools")
    assert_kind_of Array, tools
    assert_includes tools.map { it["id"] }, tools(:project_board).id
  end

  test "writes through the API and keeps the token as the writer" do
    board = tools(:project_board)
    column = @api.get("/tools/#{board.id}/board")["columns"].first
    card = @api.post("/columns/#{column["id"]}/cards", card: { title: "From MCP" })
    assert_equal "From MCP", card["title"]
    assert_equal @token.id, Event.where(kind: "card.created").last.access_token_id
  end

  test "a read-only token can't write" do
    @token.update!(permission: "read")
    column = @api.get("/tools/#{tools(:project_board).id}/board")["columns"].first
    error = assert_raises(Mcp::Api::Error) { @api.post("/columns/#{column["id"]}/cards", card: { title: "No" }) }
    assert_equal 403, error.status
  end

  test "a tool someone else has isn't found" do
    error = assert_raises(Mcp::Api::Error) { @api.get("/tools/#{tools(:other_todos).id}/todo") }
    assert_includes [ 403, 404 ], error.status
  end
end

# frozen_string_literal: true

require "test_helper"

class SearchesApiTest < ActionDispatch::IntegrationTest
  test "a read token searches the workspace" do
    get search_path(q: "First task"), headers: api_headers(users(:one), permission: "read")

    assert_response :success
    result = response.parsed_body["results"].find { |r| r["kind"] == "card" }
    assert_equal "First task", result["title"]
    assert_equal tools(:project_board).id, result["tool_id"]
    assert_match %r{\Ahttp://www\.example\.com/tools/\d+/board\?card=\d+\z}, result["url"]
  end

  test "too short a query answers with no results rather than everything" do
    get search_path(q: "F"), headers: api_headers(users(:one), permission: "read")

    assert_response :success
    assert_equal [], response.parsed_body["results"]
  end

  test "without a token or session it answers 401" do
    get search_path(q: "First task"), as: :json

    assert_response :unauthorized
  end
end

class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "the palette gets its results as a frame, and the visit isn't remembered as a page" do
    sign_in_as users(:one)

    get search_path(q: "First task"), headers: { "Turbo-Frame" => "command_palette_search" }

    assert_response :success
    assert_select "turbo-frame#command_palette_search a.command-palette-item", text: /First task/
    assert_nil users(:one).reload.last_visited_path&.then { |path| path if path.start_with?("/search") }
  end
end

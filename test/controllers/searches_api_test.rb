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

  test "each result says its date and whether it is archived, and the totals say how many there are" do
    7.times { |i| columns(:todo).cards.create!(title: "Lemur #{i}", position: 10 + i, archived_at: (1.day.ago if i.zero?)) }

    get search_path(q: "lemur"), headers: api_headers(users(:one), permission: "read")

    body = response.parsed_body
    assert_equal 5, body["results"].size
    assert_equal({ "card" => 7 }, body["totals"])
    assert body["results"].all? { |result| result["date"].present? }
    assert_equal [ false ], body["results"].map { |result| result["archived"] }.uniq

    get search_path(q: "lemur", kind: "card"), headers: api_headers(users(:one), permission: "read")

    body = response.parsed_body
    assert_equal "card", body["kind"]
    assert_equal 7, body["results"].size
    assert body["results"].last["archived"]
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

  test "what was searched for is marked in the results, and the text around it stays text" do
    sign_in_as users(:one)
    columns(:todo).cards.create!(title: "<b>Bold</b> cookie dough", position: 5)

    get search_path(q: "dough cookie"), headers: { "Turbo-Frame" => "command_palette_search" }

    assert_select "a.command-palette-item mark", text: "cookie"
    assert_select "a.command-palette-item mark", text: "dough"
    assert_select "a.command-palette-item b", count: 0
    assert_includes response.body, "&lt;b&gt;Bold&lt;/b&gt;"
  end

  test "a kind with more than five results offers them all, and an archived card says so" do
    sign_in_as users(:one)
    7.times { |i| columns(:todo).cards.create!(title: "Lemur #{i}", position: 10 + i, archived_at: (1.day.ago if i.zero?)) }

    get search_path(q: "lemur"), headers: { "Turbo-Frame" => "command_palette_search" }

    assert_select "a.command-palette-item", count: 5
    assert_select "button.command-palette-item", text: /Show all 7 cards/

    get search_path(q: "lemur", kind: "card"), headers: { "Turbo-Frame" => "command_palette_search" }

    assert_select "a.command-palette-item", count: 7
    assert_select "a.command-palette-item[data-archived]", count: 1 do
      assert_select ".badge", text: "Archived"
    end
    assert_select "button.command-palette-item", text: /Back to everything found/
  end

  test "the search page opened on its own goes home: it is a frame's worth of results" do
    sign_in_as users(:one)

    get search_path(q: "First task")

    assert_redirected_to root_path
  end
end

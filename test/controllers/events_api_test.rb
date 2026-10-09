# frozen_string_literal: true

require "test_helper"

class EventsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @token = @user.access_tokens.create!(name: "Listener", permission: "read")
    @headers = { "Authorization" => "Bearer #{@token.token}", "Accept" => "application/json" }
    @board = tools(:project_board)
    @mail = tools(:my_mail)
  end

  test "asked without a number it only says where the stream is" do
    newest = Event.record("card.created", tool: @board)

    get events_path, headers: @headers

    assert_response :success
    assert_equal({ "events" => [], "cursor" => newest.id, "more" => false, "gap" => false }, response.parsed_body)
  end

  test "an empty stream starts at nought" do
    get events_path, headers: @headers

    assert_equal 0, response.parsed_body["cursor"]
  end

  test "everything after a number, oldest first, and the number to ask after next" do
    start = Event.record("card.created", tool: @board)
    moved = Event.record("card.moved", tool: @board, record: cards(:first_task), title: "First task", column: "Done", moved_from: "To Do")
    mail = Event.record("mail.received", tool: @mail, record: mails_messages(:inbox_unread), from: "ann@example.com", subject: "Hello")

    get events_path, params: { after: start.id }, headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_equal [ moved.id, mail.id ], body["events"].map { |event| event["id"] }
    assert_equal mail.id, body["cursor"]
    assert_equal false, body["more"]
    assert_equal false, body["gap"]

    first = body["events"].first
    assert_equal "card.moved", first["kind"]
    assert_equal moved.created_at.utc.iso8601, first["at"]
    assert_equal({ "id" => @board.id, "name" => @board.name, "type" => "boards" }, first["tool"])
    assert_equal "#{@board.id}/#{cards(:first_task).id}", first["ref"]
    assert_equal({ "title" => "First task", "column" => "Done", "moved_from" => "To Do" }, first["data"])
    assert_nil first["by"]
    assert_equal false, first["own"]
  end

  test "the number moves on past what is someone else's, so a quiet listener doesn't fall behind" do
    start = Event.record("card.created", tool: @board)
    theirs = Event.record("mail.received", tool: tools(:other_mail), subject: "Not yours")

    get events_path, params: { after: start.id }, headers: @headers

    assert_equal [], response.parsed_body["events"]
    assert_equal theirs.id, response.parsed_body["cursor"]
    assert_no_match "Not yours", response.body
  end

  test "who did it, and whether it was this token" do
    writer = @user.access_tokens.create!(name: "Claude", permission: "write", agent: true)
    start = Event.maximum(:id).to_i

    post column_cards_path(columns(:todo)), params: { card: { title: "From the API" } },
      headers: { "Authorization" => "Bearer #{writer.token}", "Accept" => "application/json" }
    assert_response :created

    get events_path, params: { after: start }, headers: @headers
    event = response.parsed_body["events"].sole
    assert_equal({ "id" => @user.id, "name" => @user.name, "via" => "Claude", "agent" => true }, event["by"])
    assert_equal false, event["own"]

    get events_path, params: { after: start }, headers: { "Authorization" => "Bearer #{writer.token}", "Accept" => "application/json" }
    assert_equal true, response.parsed_body["events"].sole["own"]

    get events_path, params: { after: start, skip_own: 1 }, headers: { "Authorization" => "Bearer #{writer.token}", "Accept" => "application/json" }
    assert_equal [], response.parsed_body["events"]
    assert_equal Event.maximum(:id), response.parsed_body["cursor"]

    get events_path, params: { after: start, skip_own: 1 }, headers: @headers
    assert_equal 1, response.parsed_body["events"].size, "another token's work is not this one's own"
  end

  test "since a time, for a listener that starts without a number" do
    travel_to(3.hours.ago) { Event.record("card.created", tool: @board) }
    recent = travel_to(1.hour.ago) { Event.record("card.updated", tool: @board) }
    # Fixture memberships are made as the tests start: these are from before
    Collaborator.update_all(created_at: 1.day.ago)

    get events_path, params: { since: 2.hours.ago.iso8601 }, headers: @headers

    assert_equal [ recent.id ], response.parsed_body["events"].map { |event| event["id"] }
    assert_equal recent.id, response.parsed_body["cursor"]
  end

  test "only some tools, only some kinds" do
    start = Event.maximum(:id).to_i
    card = Event.record("card.created", tool: @board)
    moved = Event.record("card.moved", tool: tools(:shared_board))
    mail = Event.record("mail.received", tool: @mail)

    get events_path, params: { after: start, tool: [ @board.id, @mail.id ] }, headers: @headers
    assert_equal [ card.id, mail.id ], response.parsed_body["events"].map { |event| event["id"] }

    get events_path, params: { after: start, kind: [ "card" ] }, headers: @headers
    assert_equal [ card.id, moved.id ], response.parsed_body["events"].map { |event| event["id"] }

    get events_path, params: { after: start, kind: [ "card.moved", "mail" ] }, headers: @headers
    assert_equal [ moved.id, mail.id ], response.parsed_body["events"].map { |event| event["id"] }
    assert_equal mail.id, response.parsed_body["cursor"]

    get events_path, params: { after: start, tool: [ tools(:other_mail).id ] }, headers: @headers
    assert_equal [], response.parsed_body["events"], "asking for a tool by its number doesn't open it"
  end

  test "a kind that doesn't exist is said, not passed over" do
    get events_path, params: { after: 0, kind: [ "card.exploded" ] }, headers: @headers

    assert_response :unprocessable_entity
    assert_match "Unknown kind: card.exploded", response.parsed_body["error"]
  end

  test "a number or a time that is none is refused" do
    get events_path, params: { after: "abc" }, headers: @headers
    assert_response :unprocessable_entity

    get events_path, params: { after: -4 }, headers: @headers
    assert_response :unprocessable_entity

    get events_path, params: { since: "yesterday-ish" }, headers: @headers
    assert_response :unprocessable_entity

    get events_path, params: { since: "2026-13-45T99:00:00Z" }, headers: @headers
    assert_response :unprocessable_entity

    get events_path, params: { after: 0, tool: { a: "b" } }, headers: @headers
    assert_response :success
    assert_equal [], response.parsed_body["events"]
  end

  test "names are one line too: a tool, a person and a token are called what somebody typed" do
    @board.update!(name: "Projects\u009B31m\u202E")
    writer = @user.access_tokens.create!(name: "Claude\e[2J", permission: "write")
    Current.access_token = writer
    Event.record("card.created", tool: @board)
    Current.reset

    get events_path, params: { after: 0 }, headers: @headers

    event = response.parsed_body["events"].last
    assert_equal "Projects 31m", event.dig("tool", "name")
    assert_equal "Claude [2J", event.dig("by", "via")
    assert_no_match(/[\u0080-\u009F\u202E\e]/, response.body)
  end

  test "more than a page comes in pages, each ending where the next begins" do
    start = Event.maximum(:id).to_i
    stub_const(EventsController, :PAGE, 2) do
      events = Array.new(5) { Event.record("card.created", tool: @board) }

      get events_path, params: { after: start }, headers: @headers
      assert_equal events.first(2).map(&:id), response.parsed_body["events"].map { |event| event["id"] }
      assert_equal true, response.parsed_body["more"]
      assert_equal events[1].id, response.parsed_body["cursor"]

      get events_path, params: { after: events[1].id }, headers: @headers
      get events_path, params: { after: response.parsed_body["cursor"] }, headers: @headers
      assert_equal [ events.last.id ], response.parsed_body["events"].map { |event| event["id"] }
      assert_equal false, response.parsed_body["more"]
    end
  end

  test "a listener that was away for longer than events are kept is told there is a gap" do
    old = travel_to(9.days.ago) { Array.new(3) { Event.record("card.created", tool: @board) } }
    kept = Event.record("card.updated", tool: @board)
    Event.purge

    get events_path, params: { after: old.first.id }, headers: @headers

    assert_equal true, response.parsed_body["gap"]
    assert_equal [ kept.id ], response.parsed_body["events"].map { |event| event["id"] }

    get events_path, params: { after: kept.id }, headers: @headers
    assert_equal false, response.parsed_body["gap"]
  end

  test "a number this server never gave is a gap too, and the stream goes on from where it is" do
    newest = Event.record("card.created", tool: @board)

    get events_path, params: { after: newest.id + 500 }, headers: @headers

    assert_equal({ "events" => [], "cursor" => newest.id, "more" => false, "gap" => true }, response.parsed_body)
  end

  test "events of a tool that is gone, or that someone was taken off, are not given" do
    start = Event.maximum(:id).to_i
    shared = tools(:shared_board)
    Event.record("card.created", tool: shared, title: "Was shared")
    shared.collaborators.where(user: @user).destroy_all

    get events_path, params: { after: start }, headers: @headers

    assert_equal [], response.parsed_body["events"]
  end

  test "without a token, or with a revoked one, nothing" do
    get events_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    @token.destroy
    get events_path, params: { after: 0 }, headers: @headers
    assert_response :unauthorized
  end

  test "it is no page" do
    sign_in_as @user

    get events_path

    assert_response :not_acceptable
  end
end

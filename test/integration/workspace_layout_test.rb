# frozen_string_literal: true

require "test_helper"

# The arrangement of someone's tiles is kept for them (WorkspaceLayout), so every
# browser they use shows the same one. The browser makes it and makes sense of it
# (workspace_controller.js); the server keeps it and counts its revisions.
class WorkspaceLayoutTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @user = users(:one)
    @board = tools(:project_board)
    sign_in_as @user
  end

  test "an arrangement is kept, and the workspace page starts from it" do
    get workspace_path
    assert_select "[data-controller~='workspace'][data-workspace-revision-value='0']"

    keep arrangement, revision: 0

    assert_response :success
    assert_equal 1, response.parsed_body["revision"]
    assert_equal tool_board_path(@board), @user.reload.workspace_layout.state.dig("tiles", "tabc", "url")

    get workspace_path
    assert_select "[data-controller~='workspace'][data-workspace-revision-value='1']"
    kept = JSON.parse(css_select("[data-controller~='workspace']").first["data-workspace-kept-value"])
    assert_equal "Plans", kept.dig("desks", "1", "name")
    assert_equal 0.4, kept.dig("desks", "1", "tree", "ratio")
  end

  test "another browser asks for what is kept" do
    keep arrangement, revision: 0

    get workspace_path(format: :json)

    assert_response :success
    assert_equal 1, response.parsed_body["revision"]
    assert_equal %w[desk desks tiles], response.parsed_body["state"].keys.sort
  end

  test "with nothing kept yet, that is what a browser is told" do
    get workspace_path(format: :json)

    assert_equal({ "revision" => 0, "state" => {} }, response.parsed_body)
  end

  test "an arrangement made from an older one is refused, and gets the one that is kept" do
    keep arrangement, revision: 0
    keep arrangement(desk: 2), revision: 1
    assert_response :success

    # A browser that was asleep through that
    keep arrangement(desk: 3), revision: 1

    assert_response :conflict
    assert_equal 2, response.parsed_body["revision"]
    assert_equal 2, response.parsed_body.dig("state", "desk")
    assert_equal 2, @user.workspace_layout.reload.state["desk"]
  end

  test "the other browsers of this person hear of it, with who it came from" do
    assert_broadcast_on("notifications:#{@user.id}", type: "workspace", revision: 1, by: "window-1") do
      keep arrangement, revision: 0, client: "window-1"
    end
  end

  test "a refused arrangement is no news to anyone" do
    keep arrangement, revision: 0

    assert_no_broadcasts("notifications:#{@user.id}") do
      keep arrangement(desk: 2), revision: 0
    end
  end

  test "only an arrangement is kept, and not one of any size" do
    keep arrangement.merge(anything: "else"), revision: 0
    assert_equal %w[desk desks tiles], @user.workspace_layout.state.keys.sort

    long = arrangement.merge(tiles: { tabc: { url: tool_board_path(@board), title: "x" * 70_000 } })
    keep long, revision: 1

    assert_response :unprocessable_entity
    assert_equal 1, @user.workspace_layout.reload.revision
  end

  test "everyone has an arrangement of their own" do
    keep arrangement, revision: 0

    sign_in_as users(:two)
    get workspace_path(format: :json)

    assert_equal 0, response.parsed_body["revision"]
  end

  test "an access token doesn't arrange anyone's tiles" do
    patch workspace_path, params: { state: arrangement, revision: 0 }, headers: api_headers(@user), as: :json

    assert_response :forbidden
    assert_nil @user.workspace_layout
  end

  test "it goes with its person" do
    leaver = User.create!(first_name: "Leaving", last_name: "Person", email_address: "leaving@example.com", password: "a long enough password")
    WorkspaceLayout.create!(user: leaver)

    assert_difference -> { WorkspaceLayout.count }, -1 do
      leaver.destroy!
    end
  end

  private

  def keep(state, revision:, client: nil)
    patch workspace_path, params: { state: state, revision: revision, client: client }.compact, as: :json
  end

  def arrangement(desk: 1)
    {
      desk: desk,
      desks: { "1" => { tree: { split: "row", ratio: 0.4, first: { tile: "tabc" }, second: { tile: "tdef" } }, focus: "tabc", alone: false, name: "Plans" } },
      tiles: { tabc: { url: tool_board_path(@board), title: "Project Board" }, tdef: { url: tool_path(tools(:my_files)), title: "" } }
    }
  end
end

# frozen_string_literal: true

require "test_helper"

# Whatever changes something in a tool says so to the pages that have the tool open
# (AnnouncesChanges), so a board shows a card made from the CLI without being loaded
# again. Every action that writes inside a tool does, by itself; the ones below
# don't, each for a reason. A new action that should keep quiet fails this test until
# it is listed here.
#
# For the tools whose pages listen (ApplicationHelper::LIVE_TOOL_TYPES) every way to
# change them is tried as well: an action that writes and isn't tried fails too.
class ChangesAnnouncedTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  # Something of your own that nobody else's page shows: that you have seen a tool or
  # read a chat, that it is muted for you, a download
  YOUR_OWN = %w[
    tools/visits#create
    tools/chats/reads#create
    tools/mutes#create
    tools/mutes#destroy
    tools/files/downloads#create
  ].freeze

  # Shown by the tool's own stream as it happens: a chat's messages and reactions
  # (Turbo Streams), who is in a call (the notification stream)
  SHOWN_AS_IT_HAPPENS = %w[
    tools/chats/messages#create
    tools/chats/messages#update
    tools/chats/messages#destroy
    tools/chats/messages/reactions#create
    tools/chats/messages/reactions#destroy
    tools/rooms/activities#create
    tools/rooms/activities#destroy
  ].freeze

  # Nothing in the tool changes: a pass into a call, a notification to someone named
  NOTHING_IN_THE_TOOL = %w[
    tools/rooms/tokens#create
    tools/docs/documents/mentions#create
  ].freeze

  # Starts a job, and the change is the job's to announce
  A_JOBS = %w[
    tools/mails/syncs#create
    tools/calendars/syncs#create
  ].freeze

  WRITES = %w[POST PATCH PUT DELETE].freeze

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "every action that writes inside a tool announces it, but for the ones listed" do
    quiet = writes.reject { |controller, action| controller.announces_change?(action) }
      .map { |controller, action| "#{controller.controller_path}##{action}" }
    listed = YOUR_OWN + SHOWN_AS_IT_HAPPENS + NOTHING_IN_THE_TOOL + A_JOBS

    assert_empty quiet - listed, "These keep quiet about what they change. List each in #{self.class.name} with its reason."
    assert_empty listed - quiet, "These announce what they change now (or are gone): take them off the list in #{self.class.name}."
  end

  test "every way to change a board is heard by the pages that have it open" do
    tool = tools(:project_board)
    todo, doing = columns(:todo), columns(:in_progress)
    card = cards(:first_task)
    file = -> { { file: fixture_file_upload("sample.png", "image/png") } }

    tried = [
      announced(tool) { post column_cards_path(todo), params: { card: { title: "New" } }, as: :json },
      announced(tool) { patch column_positions_path(doing), params: { card_ids: [ card.id ] }, as: :json },
      announced(tool) { patch tool_board_card_path(tool, card), params: { card: { color: "red" } }, as: :json },
      announced(tool) { patch tool_board_card_position_path(tool, card), params: { column_id: todo.id }, as: :json },
      announced(tool) { post tool_board_card_comments_path(tool, card), params: { body: "Looks good" }, as: :json },
      announced(tool) { delete tool_board_card_comment_path(tool, card, card.comments.last), as: :json },
      announced(tool) { post tool_board_card_attachments_path(tool, card), params: file.call, headers: { "Accept" => "application/json" } },
      announced(tool) { delete tool_board_card_attachment_path(tool, card, card.attachments.last), as: :json },
      announced(tool) { post tool_board_card_archive_path(tool, card), as: :json },
      announced(tool) { delete tool_board_card_archive_path(tool, card), as: :json },
      announced(tool) { delete tool_board_card_path(tool, card), as: :json },
      announced(tool) { post tool_board_columns_path(tool), params: { name: "Later" }, as: :json },
      announced(tool) { patch tool_board_column_path(tool, doing), params: { name: "Doing" }, as: :json },
      announced(tool) { patch tool_board_positions_path(tool), params: { column_ids: [ doing.id, todo.id ] }, as: :json },
      announced(tool) { delete tool_board_column_path(tool, doing), as: :json }
    ]

    assert_empty writes_of("tools/boards", "columns") - tried, "These change a board and aren't tried here"
  end

  test "every way to change a todo list is heard by the pages that have it open" do
    tool = tools(:my_todos)
    main, backlog = todo_lists(:main), todo_lists(:backlog)
    item = todo_items(:pending_one)
    file = -> { { file: fixture_file_upload("sample.png", "image/png") } }

    tried = [
      announced(tool) { post todo_list_items_path(main), params: { item: { title: "New" } }, as: :json },
      announced(tool) { patch todo_list_positions_path(backlog), params: { item_ids: [ item.id ] }, as: :json },
      announced(tool) { patch tool_todo_item_path(tool, item), params: { item: { title: "Renamed" } }, as: :json },
      announced(tool) { patch tool_todo_item_position_path(tool, item), params: { todo_list_id: main.id }, as: :json },
      announced(tool) { post tool_todo_item_completion_path(tool, item), as: :json },
      announced(tool) { delete tool_todo_item_completion_path(tool, item), as: :json },
      announced(tool) { post tool_todo_item_comments_path(tool, item), params: { body: "On it" }, as: :json },
      announced(tool) { delete tool_todo_item_comment_path(tool, item, item.comments.order(:id).last), as: :json },
      announced(tool) { post tool_todo_item_attachments_path(tool, item), params: file.call, headers: { "Accept" => "application/json" } },
      announced(tool) { delete tool_todo_item_attachment_path(tool, item, item.attachments.last), as: :json },
      announced(tool) { delete tool_todo_item_path(tool, item), as: :json },
      announced(tool) { post tool_todo_lists_path(tool), params: { title: "Later" }, as: :json },
      announced(tool) { patch tool_todo_list_path(tool, backlog), params: { title: "Someday" }, as: :json },
      announced(tool) { patch tool_todo_positions_path(tool), params: { list_ids: [ backlog.id, main.id ] }, as: :json },
      announced(tool) { delete tool_todo_list_path(tool, backlog), as: :json }
    ]

    assert_empty writes_of("tools/todos", "todo_lists") - tried, "These change a todo list and aren't tried here"
  end

  test "a change made with an access token is announced like any other" do
    tool = tools(:project_board)

    assert_broadcast_on(stream(tool), type: "changed", tool_id: tool.id) do
      post column_cards_path(columns(:todo)), params: { card: { title: "From a terminal" } }, headers: api_headers(@user), as: :json
    end
    assert_response :created
  end

  test "the announcement names the request, so the page that sent it knows its own" do
    tool = tools(:project_board)

    assert_broadcast_on(stream(tool), type: "changed", tool_id: tool.id, by: "a-request-of-mine") do
      post column_cards_path(columns(:todo)), params: { card: { title: "New" } }, headers: { "X-Turbo-Request-Id" => "a-request-of-mine" }, as: :json
    end
  end

  test "it says that something changed, and nothing of what" do
    tool = tools(:project_board)
    post column_cards_path(columns(:todo)), params: { card: { title: "Nobody else's business" } }, as: :json

    said = broadcasts(stream(tool)).map { |message| ActiveSupport::JSON.decode(message) }
    assert_equal [ { "type" => "changed", "tool_id" => tool.id } ], said
  end

  test "looking changes nothing, and neither does a change that was refused" do
    tool = tools(:project_board)

    assert_no_broadcasts(stream(tool)) do
      get tool_board_path(tool)
      get tool_board_path(tool), as: :json
      post column_cards_path(columns(:todo)), params: { card: { title: "" } }, as: :json
      assert_response :unprocessable_entity
    end
  end

  test "someone who isn't let into a tool announces nothing in it" do
    tool = tools(:project_board)
    sign_in_as users(:two)
    assert_not tool.accessible_by?(users(:two))

    assert_no_broadcasts(stream(tool)) do
      post column_cards_path(columns(:todo)), params: { card: { title: "Let me in" } }, as: :json
      assert_response :forbidden
    end
  end

  test "a column folded away for yourself is nobody else's to hear of" do
    tool = tools(:project_board)

    assert_no_broadcasts(stream(tool)) do
      patch tool_board_column_path(tool, columns(:todo)), params: { collapsed: true }, as: :json
      assert_response :ok
    end
  end

  test "what you have seen or read is your own" do
    assert_no_broadcasts(stream(tools(:project_board))) do
      post tool_visit_path(tools(:project_board))
      assert_response :no_content
    end
  end

  private
    def stream(tool)
      PresenceChannel.broadcasting_for(tool)
    end

    # Does what the block asks, checks that it went well and was announced once to the
    # tool's pages, and says which action it was
    def announced(tool, &request)
      assert_broadcasts(stream(tool), 1, &request)
      assert_operator response.status, :<, 400, "#{self.request.method} #{self.request.path} answered #{response.status}: #{response.body.first(200)}"

      "#{self.request.params[:controller]}##{self.request.params[:action]}"
    end

    # Every action that writes for someone who is let into a tool
    def writes
      Rails.application.eager_load!

      Rails.application.routes.routes.filter_map do |route|
        next unless WRITES.include?(route.verb)

        controller = "#{route.defaults[:controller]}_controller".camelize.safe_constantize
        action = route.defaults[:action]
        next unless controller && controller < ApplicationController && controller.include?(ToolAuthorization)

        [ controller, action ] if controller.action_methods.include?(action)
      end.uniq
    end

    def writes_of(*namespaces)
      writes.map { |controller, action| "#{controller.controller_path}##{action}" }
        .select { |name| namespaces.any? { |namespace| name.start_with?("#{namespace}/") } }
    end
end

# frozen_string_literal: true

require "application_system_test_case"
require "net/http"

# A tool's page shows what changes in the tool while it is open, without being
# loaded again: here the change comes through the API with an access token, the way
# the CLI makes it (AnnouncesChanges, live_controller.js).
class LiveUpdatesTest < ApplicationSystemTestCase
  # Whether a page knows of a change it has not drawn yet
  BEHIND = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('%s'), 'live').refresher.behind"

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "a board shows a card that was made, moved, coloured and commented on elsewhere" do
    tool = tools(:project_board)
    open_live tool_board_path(tool)

    created = through_the_api :post, column_cards_path(columns(:todo)), card: { title: "From a terminal" }
    card = "#board-card-#{created["id"]}"
    assert_selector "#column-#{columns(:todo).id}-cards #{card}", text: "From a terminal"

    through_the_api :patch, tool_board_card_position_path(tool, created["id"]), column_id: columns(:in_progress).id
    assert_selector "#column-#{columns(:in_progress).id}-cards #{card}"

    through_the_api :patch, tool_board_card_path(tool, created["id"]), card: { color: "red" }
    assert_selector "#{card} [style*='background-color']"

    through_the_api :post, tool_board_card_comments_path(tool, created["id"]), body: "Looks good"
    assert_selector "#{card} span", text: /\A\s*1\s*\z/

    assert_same_page
  end

  test "a todo list shows a todo that was added and one that was ticked off elsewhere" do
    tool = tools(:my_todos)
    item = todo_items(:pending_one)
    open_live tool_todo_path(tool)
    assert_no_checked_field "todo-item-#{item.id}-completion"

    created = through_the_api :post, todo_list_items_path(todo_lists(:main)), item: { title: "From a terminal" }
    assert_selector "#todo-item-#{created["id"]}", text: "From a terminal"

    through_the_api :post, tool_todo_item_completion_path(tool, item)
    assert_selector "#todo-item-#{item.id}.todo-item-completed"

    assert_same_page
  end

  test "a files tool shows a folder that was made and a file that was renamed elsewhere" do
    tool = tools(:my_files)
    open_live tool_files_path(tool)
    assert_selector "[data-item-name]", text: "readme.txt"

    through_the_api :post, tool_files_folders_path(tool), name: "From a terminal"
    assert_selector "[data-item-type='folder'] [data-item-name]", text: "From a terminal"

    through_the_api :patch, tool_files_item_path(tool, file_items(:readme)), file: { name: "read-me.txt" }
    assert_selector "[data-item-type='file'] [data-item-name]", text: "read-me.txt"
    assert_no_selector "[data-item-name]", text: "readme.txt"

    assert_same_page
  end

  test "files that are picked stay picked, and the page catches up when they are let go" do
    tool = tools(:my_files)
    open_live tool_files_path(tool)

    find("[data-item-type='file'][data-item-id='#{file_items(:readme).id}']").click
    assert_text "1 selected"

    through_the_api :post, tool_files_folders_path(tool), name: "Meanwhile"
    assert_waiting
    assert_text "1 selected"
    assert_no_selector "[data-item-name]", text: "Meanwhile"

    send_keys :escape
    assert_no_text "1 selected"
    assert_selector "[data-item-name]", text: "Meanwhile"
    assert_same_page
  end

  test "a documents list shows a document that was written and one that was renamed elsewhere" do
    tool = tools(:my_docs)
    open_live tool_docs_path(tool)

    created = through_the_api :post, tool_docs_documents_path(tool), docs_document: { title: "From a terminal" }
    assert_selector "[data-document-id='#{created["id"]}']", text: "From a terminal"

    through_the_api :patch, tool_docs_document_path(tool, docs_documents(:meeting_notes)), docs_document: { title: "Minutes of the meeting" }
    assert_selector "[data-document-id='#{docs_documents(:meeting_notes).id}']", text: "Minutes of the meeting"

    assert_same_page
  end

  test "a calendar shows an event that was planned elsewhere, and loses one that was called off" do
    tool = tools(:my_calendar)
    today = Time.find_zone(@user.timezone.presence || "UTC").today
    open_live tool_calendar_path(tool)

    created = through_the_api :post, tool_calendar_events_path(tool),
      calendars_event: { summary: "From a terminal", start_time: "#{today} 14:00", end_time: "#{today} 15:00" }
    assert_text "From a terminal"

    through_the_api :delete, tool_calendar_event_path(tool, created["id"])
    assert_no_text "From a terminal"

    assert_same_page
  end

  test "a document that is open, and a form, are not such pages" do
    visit tool_docs_document_path(tools(:my_docs), docs_documents(:meeting_notes))
    wait_for_stimulus "presence", "main"
    assert_no_selector "main[data-controller~='live']"

    visit new_tool_calendar_event_path(tools(:my_calendar))
    wait_for_stimulus "presence", "main"
    assert_no_selector "main[data-controller~='live']"
  end

  test "a page with a card's title half written waits, and shows the change once that is gone" do
    tool = tools(:project_board)
    open_live tool_board_path(tool)

    # Half a title, left for a moment: the cursor is somewhere else
    title = "#board-column-#{columns(:todo).id} textarea[name='card[title]']"
    find("#board-column-#{columns(:todo).id}").click_on "Add card"
    find(title).set("Half a tho")
    page.execute_script("document.activeElement.blur()")

    created = through_the_api :post, column_cards_path(columns(:done)), card: { title: "Meanwhile" }
    assert_waiting
    assert_no_selector "#board-card-#{created["id"]}"
    assert_equal "Half a tho", find(title).value

    find("#board-column-#{columns(:todo).id}").click_on "Cancel"
    assert_selector "#board-card-#{created["id"]}", text: "Meanwhile"
    assert_same_page
  end

  test "a card that is open stays open, and the board behind it catches up when it closes" do
    tool = tools(:project_board)
    open_live tool_board_path(tool)

    find("#board-card-#{cards(:first_task).id}").click
    assert_selector "dialog[open]", text: "First task"

    created = through_the_api :post, column_cards_path(columns(:done)), card: { title: "Meanwhile" }
    assert_waiting
    assert_selector "dialog[open]", text: "First task"

    send_keys :escape
    assert_no_selector "dialog[open]"
    assert_selector "#board-card-#{created["id"]}", text: "Meanwhile"
  end

  test "what a colleague does in their browser shows in yours" do
    tool = tools(:shared_board)
    column = tool.board.columns.create!(name: "Doing", position: 0)
    open_live tool_board_path(tool)

    using_session("colleague") do
      sign_in_as users(:two)
      visit tool_board_path(tool)
      find("#board-column-#{column.id}").click_on "Add card"
      find("#board-column-#{column.id} textarea[name='card[title]']").send_keys("From across the room", :enter)
      assert_selector ".board-card", text: "From across the room"
    end

    assert_selector ".board-card", text: "From across the room"
    assert_same_page
  end

  test "the page that made a change doesn't draw itself again for it" do
    tool = tools(:my_todos)
    item = todo_items(:pending_one)
    open_live tool_todo_path(tool)
    # What the page makes of each change it is told of: one more to draw, or its own
    page.execute_script("window.heard = []
      document.querySelector('main').addEventListener('presence:changed', () => window.heard.push(#{BEHIND % "main"}))")

    find("#todo-item-#{item.id}-completion").click
    assert_db_change -> { item.reload.completed? }
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The page wasn't told of the change" if page.evaluate_script("window.heard.length").zero?
    end
    assert_equal [ false ], page.evaluate_script("window.heard")

    # Someone else's is one to draw
    through_the_api :post, todo_list_items_path(todo_lists(:main)), item: { title: "From a terminal" }
    assert_selector ".todo-item", text: "From a terminal"
    assert_equal [ false, true ], page.evaluate_script("window.heard")
  end

  test "a tile in the workspace shows it as well" do
    tool = tools(:project_board)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(tool))
    wait_for_stimulus "workspace"

    created = nil
    within_frame(find(".workspace-tile iframe")) do
      assert_selector "h1", text: tool.name
      wait_until_listening
      created = through_the_api :post, column_cards_path(columns(:todo)), card: { title: "From a terminal" }
      assert_selector "#board-card-#{created["id"]}", text: "From a terminal"
    end
  end

  test "a tile in the workspace's own page shows it, and nothing but that tile is drawn again" do
    tool = tools(:my_todos)
    tile = ".workspace-tile turbo-frame.tile-frame"
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path("in-page": "todos", open: tool_path(tool))
    wait_for_stimulus "workspace"
    assert_selector "#{tile} .tile-page h1", text: tool.name
    wait_until_listening "#{tile} .tile-page"
    page.execute_script("window.pageBefore = document.querySelector('.workspace-bar'); window.tileBefore = document.querySelector(arguments[0])", "#{tile} .tile-page")

    created = through_the_api :post, todo_list_items_path(todo_lists(:main)), item: { title: "From a terminal" }

    assert_selector "#{tile} #todo-item-#{created["id"]}", text: "From a terminal"
    assert page.evaluate_script("window.pageBefore === document.querySelector('.workspace-bar')"), "The page around the tiles was replaced"
    assert page.evaluate_script("window.tileBefore === document.querySelector(arguments[0])", "#{tile} .tile-page"), "The tile's page was replaced, not laid over"
    assert_current_path workspace_path

    # And what is done in the tile itself is its own, not one more to draw
    item = todo_items(:pending_one)
    page.execute_script("window.heard = []
      window.tileBefore.addEventListener('presence:changed', () => window.heard.push(#{BEHIND % "#{tile} .tile-page"}))")
    find("#{tile} #todo-item-#{item.id}-completion").click
    assert_db_change -> { item.reload.completed? }
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The tile wasn't told of the change" if page.evaluate_script("window.heard.length").zero?
    end
    assert_equal [ false ], page.evaluate_script("window.heard")
  ensure
    page.execute_script("try { localStorage.removeItem('dobase:workspace:in-page') } catch (error) {}")
  end

  test "someone who can't open the tool hears nothing of it" do
    tool = tools(:project_board)
    assert_not tool.accessible_by?(users(:two))

    using_session("colleague") do
      sign_in_as users(:two)
      open_live tool_board_path(tools(:shared_board))
      page.execute_script("window.heard = 0; document.querySelector('main').addEventListener('presence:changed', () => window.heard++)")
    end

    through_the_api :post, column_cards_path(columns(:todo)), card: { title: "Not theirs" }
    # (their own board does tell them: what they'd hear is heard by now)
    through_the_api :post, column_cards_path(tools(:shared_board).board.columns.create!(name: "Shared", position: 0)), card: { title: "Theirs too" }

    using_session("colleague") do
      assert_selector ".board-card", text: "Theirs too"
      assert_equal 1, page.evaluate_script("window.heard")
      assert_no_text "Not theirs"
    end
  end

  private
    def open_live(path)
      visit path
      wait_until_listening
      page.execute_script("window.sameWindow = true")
    end

    # Listening, not only drawn: what is announced before that is not heard
    def wait_until_listening(selector = "main")
      wait_for_stimulus "live", selector
      page.document.synchronize do
        raise Capybara::ExpectationNotMet, "The page isn't listening to its tool yet" unless page.evaluate_script(
          "Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{selector.to_json}), 'presence').listening === true")
      end
    end

    # Nothing loaded the page again: what was put on its window is still there
    def assert_same_page
      assert page.evaluate_script("window.sameWindow === true"), "The page was loaded again"
    end

    # The page heard of a change, had its moment to draw it, and didn't
    def assert_waiting
      page.document.synchronize do
        raise Capybara::ExpectationNotMet, "The page has heard of no change it still has to draw" unless page.evaluate_script(BEHIND % "main")
      end
      sleep 0.6
      assert page.evaluate_script(BEHIND % "main"), "The page drew itself again while it was in use"
    end

    # What the CLI does: a request to the JSON API with an access token
    def through_the_api(verb, path, user: @user, **body)
      @tokens ||= {}
      @tokens[user] ||= user.access_tokens.create!(name: "Terminal", permission: "write").token

      uri = URI.join(page.server_url, path)
      request = Net::HTTP.const_get(verb.to_s.capitalize).new(uri,
        "Authorization" => "Bearer #{@tokens[user]}", "Accept" => "application/json", "Content-Type" => "application/json")
      request.body = body.to_json
      response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }

      assert_operator response.code.to_i, :<, 300, "#{verb.upcase} #{path} answered #{response.code}: #{response.body}"
      response.body.present? ? JSON.parse(response.body) : nil
    end
end

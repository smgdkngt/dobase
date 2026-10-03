# frozen_string_literal: true

require "application_system_test_case"

class WorkspaceTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  # A tile that is in the room (not on another desktop, not on its way out)
  SHOWING_TILE = ".workspace-tile:not([hidden], [data-leaving])"

  # The launcher: the search at the top of the menu, while the menu is in
  MENU_SEARCH = ".sidebar.open [data-controller~='command-palette']"

  setup do
    @board = tools(:project_board)
    @files = tools(:my_files)
    @todos = tools(:my_todos)
    sign_in_as users(:one)
    # As it is outside the tests: a wide window works in the workspace
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path
    wait_for_stimulus "workspace"
    # A workspace with nothing in it yet opens with the tool you were last on
    within_tile(0) { assert_selector "h1", text: @board.name }
  end

  test "tools open as tiles that arrange themselves: side by side, then stacked" do
    assert_equal 1, tiles.size
    within_tile(0) { assert_no_selector ".sidebar" }

    launch @files
    first, second = tiles
    assert_in_delta first[:width], second[:width], 2
    assert_operator first[:left] + first[:width], :<=, second[:left]
    assert_equal first[:top], second[:top]

    launch @todos
    _, second, third = tiles
    assert_equal second[:left], third[:left]
    assert_operator second[:top] + second[:height], :<=, third[:top]
    assert_current_path workspace_path
    within_tile(2) { assert_selector "h1", text: @todos.name }
  end

  test "a new tile takes the room of the biggest one when the one you are on is too small, and the next desktop when none has room" do
    page.driver.browser.manage.window.resize_to(1100, 760)
    launch @files
    launch @todos
    assert_equal 3, tiles.size

    # The tile you are on (bottom right) can't be halved; the big one on the left can
    launch tools(:my_docs)
    board, _, _, docs = tiles
    assert_equal board[:left], docs[:left]
    assert_operator board[:top] + board[:height], :<=, docs[:top]

    launch tools(:shared_board), on_new_desktop: true
    assert_equal 1, tiles.size
    assert_selector ".workspace-desk[aria-current='true']", text: "2"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a tool that is open already is gone to, not opened twice" do
    launch @files
    assert_focused 1

    launch @board, new_tile: false

    assert_focused 0
    assert_equal 2, tiles.size
  end

  test "keys go from tile to tile, set one alone, and close it" do
    launch @files
    assert_focused 1

    press :arrow_left
    assert_focused 0

    # From inside a tile, where the keyboard usually is
    within_tile(0) { press :arrow_right }
    assert_focused 1

    press "f"
    assert_equal 1, tiles.size
    press "f"
    assert_equal 2, tiles.size

    press "w"
    assert_equal 1, tiles.size
    within_tile(0) { assert_selector "h1", text: @board.name }
  end

  test "a tool launched from inside a tile gets the keyboard, and closing closes that one" do
    launch @files
    within_tile(0) { find("h1").click }
    assert_focused 0

    # Keys go to wherever the keyboard is, as they do for a person
    type_keys mac? ? :meta : :control, "k"
    within MENU_SEARCH do
      input = find("input[data-command-palette-target='input']")
      input.set(@todos.name)
      assert_selector ".command-palette-item.selected", text: @todos.name
      input.send_keys(:enter)
    end
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 3
    within_tile(2) { assert_selector "h1", text: @todos.name }
    assert_focused 2

    type_keys(*(mac? ? %i[control alt] : %i[alt]), "w")

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 2
    within_tile(0) { assert_selector "h1", text: @board.name }
    within_tile(1) { assert_selector "h1", text: @files.name }
  end

  test "a tile sent away from a page that is gone goes back to its tool" do
    within_tile(0) { page.execute_script("window.before = true; Turbo.visit('#{tool_board_card_path(@board, 0)}')") }

    # Its tool's page, loaded afresh: not the page it was on, still standing
    within_tile(0) do
      page.document.synchronize do
        raise Capybara::ExpectationNotMet, "the tile is still on the page it was on" if page.evaluate_script("window.before")
      end
      assert_selector "h1", text: @board.name
    end
    assert_equal 1, tiles.size
  end

  test "a narrow window whose tile is on a tool that is gone gets a tool that exists" do
    launch @todos
    @todos.destroy
    page.driver.browser.manage.window.resize_to(900, 900)

    visit workspace_path

    assert_selector "main h1"
    assert_no_selector "[data-controller~='workspace']"
    assert_match %r{\A/tools/\d+}, page.current_path
    assert_no_match %r{\A/tools/#{@todos.id}\b}, page.current_path
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a narrow window whose tile is on a page that sends it back to the start doesn't go round" do
    # The tile's address is a tool of yours, on a page of it that refuses and sends you to the start
    page.execute_script(<<~JS)
      window.addEventListener("pagehide", () => {
        const key = "dobase:workspace:#{users(:one).id}"
        const kept = JSON.parse(localStorage.getItem(key))
        kept.tiles[kept.desks[kept.desk].focus].url = "#{tool_board_card_path(@board, 0)}"
        localStorage.setItem(key, JSON.stringify(kept))
      })
    JS
    page.driver.browser.manage.window.resize_to(900, 900)

    visit workspace_path

    assert_selector "main h1"
    assert_no_selector "[data-controller~='workspace']"
    assert_match %r{\A/tools/\d+}, page.current_path
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a first visit says what is different here, once" do
    assert_selector ".workspace-hint", text: "Every tool you open is a tile here"

    within(".workspace-hint") { click_on "Got it" }
    assert_no_selector ".workspace-hint"

    visit workspace_path
    wait_for_stimulus "workspace"
    within_tile(0) { assert_selector "h1", text: @board.name }
    assert_no_selector ".workspace-hint"
  end

  test "a page gets a tile of its own with Shift in the launcher, and with Alt and a click in a tile" do
    docs = tools(:my_docs)
    launch docs
    assert_equal 2, tiles.size

    # The tool is open, so the launcher would go to it; with Shift it opens beside it
    find(".workspace-bar-btn[aria-label='Menu']").click
    within MENU_SEARCH do
      input = find("input[data-command-palette-target='input']")
      input.set(docs.name)
      assert_selector ".command-palette-item.selected", text: docs.name
      assert_text "In a new tile"
      input.send_keys([ :shift, :enter ])
    end
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 3

    within_tile(2) { find("a", text: docs_documents(:meeting_notes).title).click(:alt) }
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 4
    within_tile(3) { assert_selector "h1", text: docs_documents(:meeting_notes).title }
    within_tile(2) { assert_selector "h1", text: docs.name }
  end

  test "the menu opens with its search, and down from there the arrow keys go through the tools" do
    press "m"
    assert_selector ".sidebar.open"
    assert_selector "#{MENU_SEARCH} input:focus"

    # Nothing typed: the menu is your tools as you arranged them
    assert_selector ".sidebar.open [data-sidebar-tool-link]", text: @board.name

    type_keys :arrow_down
    assert_selector "[data-sidebar-tool-link]:focus"
    type_keys :arrow_up
    assert_selector "#{MENU_SEARCH} input:focus"

    type_keys :arrow_down
    type_keys :arrow_down
    opened = page.evaluate_script("document.activeElement.dataset.toolName")
    type_keys :enter

    assert_no_selector ".sidebar.open"
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 2
    within_tile(1) { assert_selector "h1", text: opened }
  end

  test "the launcher's key, the menu's key and the logo open the same menu, with everything the sidebar has" do
    type_keys(mac? ? :meta : :control, "k")
    assert_selector "#{MENU_SEARCH} input:focus"
    within ".sidebar.open" do
      assert_selector "[data-sidebar-tool-link]", text: @files.name
      assert_selector ".sidebar-tool-menu-btn", visible: :all, minimum: 1
      assert_selector "button[popovertarget='sidebar-add-menu']"
    end

    # Typing finds, in the place of the list; emptied, the list is back
    find("#{MENU_SEARCH} input").set(@todos.name)
    assert_selector "#{MENU_SEARCH} .command-palette-item.selected", text: @todos.name
    assert_no_selector ".sidebar.open [data-sidebar-tool-link]"
    find("#{MENU_SEARCH} input").set("")
    assert_selector ".sidebar.open [data-sidebar-tool-link]", text: @todos.name

    type_keys :escape
    assert_no_selector ".sidebar.open"

    find(".workspace-bar-btn[aria-label='Menu']").click
    assert_selector "#{MENU_SEARCH} input:focus"

    # Reordering is where it always was
    find(".sidebar.open button[popovertarget='sidebar-add-menu']").click
    click_on "Reorder"
    assert_selector ".sidebar.open .reorder-mode", minimum: 1
  end

  test "the menu's button says it is open, keeps the tiles out of reach, and gets the keyboard back" do
    menu = find(".workspace-bar-btn[aria-label='Menu']")
    assert_equal "false", menu["aria-expanded"]

    menu.send_keys(:enter)
    assert_selector ".sidebar.open"
    assert_selector ".workspace-bar-btn[aria-label='Menu'][aria-expanded='true']"
    assert_selector "#workspace-tiles[inert]"
    assert_selector "#{MENU_SEARCH} input:focus"

    type_keys :escape
    assert_no_selector ".sidebar.open"
    assert_selector ".workspace-bar-btn[aria-label='Menu'][aria-expanded='false']:focus"
    assert_no_selector "#workspace-tiles[inert]"
  end

  test "a tile, its frame and its close button are called after what is in it" do
    launch @files

    assert_selector ".workspace-tile[aria-label='#{@files.name}'][aria-current='true']"
    assert_selector ".workspace-tile[aria-label='#{@board.name}']:not([aria-current])"
    assert_selector ".workspace-tile iframe[title='#{@files.name}']"
    assert_selector ".workspace-tile button[aria-label='Close #{@files.name}']", visible: :all
    assert_selector "[data-workspace-target='status']", text: "#{@files.name} opened", visible: :all
  end

  test "what the keys do is in the launcher by name" do
    launch @files
    assert_equal 2, tiles.size

    find(".workspace-bar-btn[aria-label='Menu']").click
    within MENU_SEARCH do
      assert_no_selector ".command-palette-item", text: "Close the tile"
      input = find("input[data-command-palette-target='input']")
      input.set("close the tile")
      assert_selector ".command-palette-item.selected", text: "Close the tile"
      input.send_keys(:enter)
    end

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 1
    within_tile(0) { assert_selector "h1", text: @board.name }
    assert_selector "[data-workspace-target='status']", text: "#{@files.name} closed", visible: :all
  end

  test "a desktop picked with the keyboard on its button leaves the keyboard there" do
    assert_selector ".workspace-desk", count: 2
    find(".workspace-desk", text: "2").send_keys(:enter)

    assert_selector ".workspace-desk[aria-current='true']:focus", text: "2"
    assert_text "Nothing open on this desktop"
    # The one in use, the one you are on; nothing further is on offer until this one is used
    assert_selector ".workspace-desk", count: 2
  end

  test "F6 goes on to the next tile, and with Shift back" do
    launch @files
    launch @todos
    assert_focused 2

    type_keys :f6
    assert_focused 0
    type_keys :shift, :f6
    assert_focused 2
  end

  test "the arrow keys go through the tool in the tile you are on" do
    type_keys :arrow_down
    within_tile(0) { assert_selector "#board-card-#{cards(:first_task).id}:focus" }

    type_keys :arrow_right
    within_tile(0) { assert_selector "#board-card-#{cards(:third_task).id}:focus" }
  end

  test "past the edge of a tool the arrows go on to the tile on that side, and back" do
    launch @files
    assert_focused 1

    # In the files tile nothing is to the left of the first thing: on to the board
    type_keys :arrow_right
    within_tile(1) { assert_selector "[data-arrow-keys-target='item']:focus" }
    type_keys :arrow_left
    assert_focused 0

    # In the board the arrows are the board's, until its last column has nothing further right
    type_keys :arrow_down
    within_tile(0) { assert_selector "#board-card-#{cards(:first_task).id}:focus" }
    6.times do
      type_keys :arrow_right
      break if focused_index == 1
      sleep 0.15
    end
    assert_focused 1
  end

  test "up from the top of a tile is the bar, and down from the bar is the tile again" do
    # (the line about the workspace lies under the bar too, until it is dismissed)
    within(".workspace-hint") { click_on "Got it" }
    type_keys :arrow_down
    within_tile(0) { assert_selector "#board-card-#{cards(:first_task).id}:focus" }

    # Up through what the board has above its cards, and past that out of the tile
    8.times do
      type_keys :arrow_up
      break if page.has_selector?(".workspace-desk:focus", wait: 0.3)
    end
    assert_selector ".workspace-desk[aria-current='true']:focus"

    type_keys :arrow_left
    assert_selector ".workspace-bar-btn[aria-label='Menu']:focus"

    type_keys :arrow_down
    page.document.synchronize do
      back = page.evaluate_script("document.activeElement === document.querySelector('.workspace-tile iframe')")
      raise Capybara::ExpectationNotMet, "the keyboard isn't back in the tile" unless back
    end
  end

  test "mail in a tile: the arrows go down the list, into a conversation and back to the list" do
    visit workspace_path(open: tool_mails_path(tools(:my_mail)))
    wait_for_stimulus "workspace"
    within_tile(1) { assert_selector ".mail-list-item" }

    # A tile is narrow: the list and the conversation take turns
    type_keys :arrow_down
    within_tile(1) do
      assert_selector ".mail-list-item.selected", count: 1
      assert_no_selector ".mail-detail-header"
    end

    type_keys :arrow_right
    within_tile(1) { assert_selector ".mail-detail-header" }

    type_keys :arrow_left
    within_tile(1) do
      assert_no_selector ".mail-detail-header"
      assert_selector ".mail-list-item.selected", count: 1
    end
  end

  test "the page around the tiles is drawn again without touching them, and not at all when the answer is no good" do
    within_tile(0) { page.execute_script("window.stillHere = true") }
    Tool.create!(name: "Made elsewhere", tool_type: tool_types(:todos), owner: users(:one))

    # No network, or a server in trouble: everything stays as it is
    page.execute_script(<<~JS)
      window.realFetch = window.fetch
      window.fetch = () => Promise.resolve(new Response("<html><body>Something went wrong</body></html>", { status: 500 }))
      document.dispatchEvent(new Event("visibilitychange"))
      window.fetch = () => Promise.reject(new TypeError("Failed to fetch"))
      document.dispatchEvent(new Event("visibilitychange"))
    JS
    sleep 0.5
    assert_selector "[data-controller~='workspace'] .workspace-bar"
    assert_no_text "Something went wrong"
    assert_no_selector "[data-sidebar-tool-link]", text: "Made elsewhere", visible: :all
    within_tile(0) { assert page.evaluate_script("window.stillHere"), "the tile was loaded again" }

    page.execute_script("window.fetch = window.realFetch; document.dispatchEvent(new Event('visibilitychange'))")
    assert_selector "[data-sidebar-tool-link]", text: "Made elsewhere", visible: :all
    within_tile(0) { assert page.evaluate_script("window.stillHere"), "the tile was loaded again" }
    assert_current_path workspace_path
  end

  test "a theme picked in the profile dialog is put on without leaving it, or the workspace" do
    # (a tile that fades into a theme by itself comes in after the window around it)
    within_tile(0) do
      page.execute_script("document.startViewTransition = (change) => { window.fadedByItself = true; change(); return {} }")
    end
    find(".workspace-bar-btn[popovertarget='sidebar-user-menu']").click
    click_on "Profile"

    within "dialog#profile-modal[open]" do
      find("[data-tabs-target='tab'][data-tab='appearance']").click
      find("button.theme-option[name='theme'][value='nord']").click
      assert_selector "button.theme-option-selected[value='nord']"
      assert_selector "button.theme-option-selected[name='theme']", count: 1
    end

    assert_selector "html[data-theme='nord']"
    assert_selector "dialog#profile-modal[open]"
    assert_current_path workspace_path
    within_tile(0) do
      assert_selector "html[data-theme='nord']"
      assert_not page.evaluate_script("window.fadedByItself === true"), "the tile faded into the theme by itself"
    end
  end

  test "the workspace's keys go with another modifier, for whoever has these taken" do
    launch @files
    assert_focused 1
    other = mac? ? [ "ctrl-meta", %i[control meta], "Ctrl+Cmd+" ] : [ "ctrl-alt", %i[control alt], "Ctrl+Alt+" ]

    find("body").send_keys("?")
    within "dialog[open]" do
      find("select[data-controller~='workspace-keys']").find("option[value='#{other[0]}']").select_option
      # The keys the page names are the new ones at once, and nothing was loaded again
      assert_selector "kbd", text: "#{other[2]}W", exact_text: true
    end
    type_keys :escape
    assert_no_selector "dialog[open]"

    # The keys as they were do nothing now; the chosen ones do
    press :arrow_left
    sleep 0.3
    assert_focused 1
    type_keys(*other[1], :arrow_left)
    assert_focused 0

    # And it is kept: the page is drawn with them the next time
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector ".workspace-tile button[title='Close this tile (#{other[2]}W)']", visible: :all, minimum: 1
  ensure
    page.driver.browser.manage.delete_cookie("workspace_keys")
  end

  test "escape lets go of things one at a time, and with nothing left to let go of it closes the tile" do
    launch @files
    assert_equal 2, tiles.size

    # A field, then the file the arrows were on, then the tile itself
    type_keys :arrow_right
    within_tile(1) { assert_selector "[data-arrow-keys-target='item']:focus" }
    type_keys :escape
    within_tile(1) { assert_no_selector "[data-arrow-keys-target='item']:focus" }
    assert_equal 2, tiles.size

    type_keys :escape
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 1
    within_tile(0) { assert_selector "h1", text: @board.name }
  end

  test "escape inside a tool goes up a level, and only closes the tile at the top of the tool" do
    docs = tools(:my_docs)
    document = docs_documents(:meeting_notes)
    visit workspace_path(open: tool_docs_document_path(docs, document))
    wait_for_stimulus "workspace"
    within_tile(1) { assert_selector "h1", text: document.title }

    # In a document: out of it, to the documents
    type_keys :escape
    within_tile(1) { assert_selector "h1", text: docs.name }
    assert_equal 2, tiles.size

    # At the top of the tool: the tile
    type_keys :escape
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 1
    within_tile(0) { assert_selector "h1", text: @board.name }
  end

  test "a click in a tile takes the keyboard there, also where the click was kept for a drag" do
    launch @files
    assert_focused 1

    # A column can be dragged by its head, and takes the press for that: no keyboard
    # moves by the click itself
    within_tile(0) { find(".board-column-expanded", match: :first).click(x: 40, y: 12) }
    assert_focused 0
    page.document.synchronize do
      there = page.evaluate_script("document.activeElement === document.querySelectorAll('.workspace-tile iframe')[0]")
      raise Capybara::ExpectationNotMet, "the keyboard isn't in the tile that was clicked" unless there
    end
  end

  test "a card's details float over all the tiles, and closing them gives the tile back" do
    launch @files
    within_tile(0) { find("#board-card-#{cards(:first_task).id}").click }

    assert_selector ".workspace-float:not([hidden]) iframe"
    assert_selector "#workspace-tiles[inert]"
    within_float do
      assert_selector "dialog#card-detail-modal[open] h2", text: "First task"
      # The page that floats is drawn as the card alone: no board to draw around it
      assert_no_selector ".board-column", visible: :all
      # As wide as the window, not as the tile it came from: the dialog has its two columns
      assert_operator page.evaluate_script("document.querySelector('dialog[open]').getBoundingClientRect().width"), :>, 700
    end
    # The tile itself opened nothing
    within_tile(0) { assert_no_selector "dialog[open]" }

    type_keys :escape
    assert_no_selector ".workspace-float iframe"
    assert_no_selector "#workspace-tiles[inert]"
    assert_equal 2, tiles.size
    page.document.synchronize do
      back = page.evaluate_script("document.activeElement === document.querySelectorAll('.workspace-tile iframe')[0]")
      raise Capybara::ExpectationNotMet, "the keyboard isn't back in the tile" unless back
    end
  end

  test "what is changed in a floating dialog shows in the tile when it closes" do
    card = cards(:first_task)
    within_tile(0) { find("#board-card-#{card.id}").click }

    within_float do
      assert_selector "dialog#card-detail-modal[open] h2", text: "First task"
      click_on "Archive card"
    end

    assert_no_selector ".workspace-float iframe"
    within_tile(0) do
      assert_selector "h1", text: @board.name
      assert_no_selector "#board-card-#{card.id}"
    end
    assert card.reload.archived?
  end

  test "a todo's and an event's details float too" do
    visit workspace_path(open: tool_todo_path(@todos))
    wait_for_stimulus "workspace"
    within_tile(1) { find("[aria-label='Open #{todo_items(:pending_one).title}']").click }
    within_float do
      assert_selector "dialog#item-detail-modal[open]", text: todo_items(:pending_one).title
      assert_no_selector ".todo-list-items", visible: :all
    end
    type_keys :escape
    assert_no_selector ".workspace-float iframe"

    calendar = tools(:my_calendar)
    visit workspace_path(open: tool_calendar_path(calendar))
    wait_for_stimulus "workspace"
    within_tile(2) { find("[data-event-id]", match: :first).click }
    within_float do
      assert_selector "dialog[open]", text: "Event Details"
      assert_selector "dialog[open] button", text: "Close"
      assert_no_selector "#calendar-week-container", visible: :all
    end
    type_keys :escape
    assert_no_selector ".workspace-float iframe"
  end

  test "an address that opens a card floats it, and the tile doesn't open it again with every reload" do
    visit workspace_path(open: tool_board_path(@board, card: cards(:second_task).id))
    wait_for_stimulus "workspace"

    within_float { assert_selector "dialog#card-detail-modal[open] h2", text: "Second task" }
    type_keys :escape
    assert_no_selector ".workspace-float iframe"

    visit workspace_path
    wait_for_stimulus "workspace"
    within_tile(0) { assert_selector "h1", text: @board.name }
    assert_no_selector ".workspace-float iframe", wait: 2
  end

  test "a notification about a tool in sight makes no sound of its own, one about a tool elsewhere does" do
    colleague = users(:two)
    # (a browser lets a page make sound once it has been touched: a click in a tile counts for the window)
    within_tile(0) { find("h1", text: @board.name).click }
    page.execute_script("window.heardSounds = []; document.addEventListener('sound:played', (event) => window.heardSounds.push(event.detail.name))")
    assert_selector "[data-tool-id='#{@board.id}'] [data-sidebar-tool-link][data-in-sight]", visible: :all
    unread = find(".workspace-bar [data-notifications-unread-count-value]", visible: :all)["data-notifications-unread-count-value"].to_i

    # About the board, which is right there in a tile
    perform_enqueued_jobs do
      CardAssignmentNotifier.with(card: cards(:first_task), assigner: colleague, tool: @board).deliver(users(:one))
    end
    assert_selector ".workspace-bar [data-notifications-unread-count-value='#{unread + 1}']", visible: :all
    assert_empty page.evaluate_script("window.heardSounds")

    # About the todos, which aren't open anywhere
    perform_enqueued_jobs do
      TodoAssignmentNotifier.with(item: todo_items(:pending_one), assigner: colleague, tool: @todos).deliver(users(:one))
    end
    assert_selector ".workspace-bar [data-notifications-unread-count-value='#{unread + 2}']", visible: :all
    assert_heard_here "notify"

    # On another desktop the board is out of sight, and its link says so
    press "2"
    assert_no_selector "[data-tool-id='#{@board.id}'] [data-sidebar-tool-link][data-in-sight]", visible: :all
  end

  test "a message in a chat on another desktop is a notification's to announce, not the chat's" do
    colleague = users(:two)
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.name = "Chat"; type.icon = "message-circle"; type.enabled = true }
    chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: users(:one))
    chat.collaborators.create!(user: colleague, role: "collaborator")
    visit workspace_path(open: tool_chat_path(chat))
    wait_for_stimulus "workspace"
    # (the hint about tiles lies over the bottom of the window until it is sent away)
    find(".workspace-hint button", text: "Got it").click
    within_tile(1) do
      # (a click in the middle of a chat's tile: the holder of the toasts lay over it once, unseen, and took every click)
      find("rhino-editor .ProseMirror").click
      assert page.evaluate_script("document.activeElement.closest('rhino-editor') !== null || document.activeElement.tagName === 'RHINO-EDITOR'"), "the click didn't reach the message box"
      page.execute_script("window.heardSounds = []; document.addEventListener('sound:played', (event) => window.heardSounds.push(event.detail.name))")
    end
    page.execute_script("window.heardSounds = []; document.addEventListener('sound:played', (event) => window.heardSounds.push(event.detail.name))")

    # In sight: the chat says so itself, and the notification keeps quiet
    perform_enqueued_jobs { chat.chat.messages.create!(user: colleague, body: "<p>Here</p>") }
    within_tile(1) do
      assert_selector ".chat-message", text: "Here"
      assert_heard_here "receive"
    end
    assert_empty page.evaluate_script("window.heardSounds")

    # On another desktop: the other way round
    press "2"
    assert_no_selector "[data-tool-id='#{chat.id}'] [data-sidebar-tool-link][data-in-sight]", visible: :all
    perform_enqueued_jobs { chat.chat.messages.create!(user: colleague, body: "<p>Still there?</p>") }
    assert_heard_here "notify"
    chat_frame = "Array.from(document.querySelectorAll('.workspace-tile iframe')).find((frame) => frame.contentWindow.location.pathname.includes('/tools/#{chat.id}'))"
    assert_equal %w[receive], page.evaluate_script("#{chat_frame}.contentWindow.heardSounds")
  end

  test "backspace outside a field is nobody's key, so it can't be 'back' in whichever tile went somewhere last" do
    backspace = <<~JS
      ((on) => {
        const key = new KeyboardEvent("keydown", { key: "Backspace", bubbles: true, cancelable: true })
        on.dispatchEvent(key)
        return key.defaultPrevented
      })
    JS

    assert page.evaluate_script("#{backspace}(document.body)"), "on the page around the tiles"
    within_tile(0) do
      assert page.evaluate_script("#{backspace}(document.body)"), "in a tile"
      assert page.evaluate_script("#{backspace}(document.querySelector('.board-card'))"), "on a card in a tile"

      # In a field it is what deletes a letter
      find("[data-board-target='addCardBtn']", match: :first).click
      assert_not page.evaluate_script("#{backspace}(document.querySelector(\"textarea[data-board-target='addCardInput']\"))")
    end
  end

  test "the bell in the bar opens the notifications over the tiles" do
    find(".workspace-bar-btn[aria-label='Notifications']").click

    assert_selector "#sidebar-notifications", text: "Notifications"
    type_keys :escape
    assert_no_selector "#sidebar-notifications"
  end

  test "the bar shows what is new on a desktop you aren't on, the menu's button what is new in a tool that isn't open, and a tool you look at is seen" do
    docs = tools(:my_docs)
    press "2"
    launch @todos, on_new_desktop: true
    press "1"
    assert_selector ".workspace-desk[aria-current='true']", text: "1"
    seen = @todos.collaborators.find_by!(user: users(:one))
    seen.update_column(:last_seen_at, 2.days.ago)
    sleep 0.5 # the notification channel has to be subscribed before anything is sent on it

    # What a notification about a tool is on the stream (the notifiers send more)
    ActionCable.server.broadcast("notifications:#{users(:one).id}", { id: 1, message: "A todo is yours", tool_id: @todos.id })
    ActionCable.server.broadcast("notifications:#{users(:one).id}", { id: 2, message: "A new document", tool_id: docs.id })

    assert_selector ".workspace-desk[data-desk='2'][data-unread] .workspace-desk-tool[data-unread]"
    assert_selector ".workspace-desk[data-desk='2'][aria-label='Desktop 2: #{@todos.name}. New in #{@todos.name}']"
    assert_no_selector ".workspace-desk[data-desk='1'][data-unread]"
    assert_selector ".workspace-bar-btn[aria-label='Menu'][data-unread][title*='#{docs.name}']"

    # The card about the desktop names what is on it; a click goes straight to the tile
    find(".workspace-desk[data-desk='2']").hover
    within ".workspace-desk-card" do
      assert_text "DESKTOP 2"
      assert_selector ".workspace-desk-card-row[data-unread]", text: @todos.name
      find(".workspace-desk-card-go", text: @todos.name).click
    end

    assert_selector ".workspace-desk[aria-current='true']", text: "2"
    assert_no_selector ".workspace-desk[data-unread]"
    assert_no_selector "[data-sidebar-tool-link][href='#{tool_path(@todos)}'][data-unread]", visible: :all
    # And the server knows: the dot doesn't come back with the next page
    assert_db_change -> { seen.reload.last_seen_at > 1.minute.ago }

    # Something new in a tool you are looking at never gets a dot
    ActionCable.server.broadcast("notifications:#{users(:one).id}", { id: 3, message: "Another todo", tool_id: @todos.id })
    sleep 0.5
    assert_no_selector ".workspace-desk[data-unread]"
    assert_no_selector "[data-sidebar-tool-link][href='#{tool_path(@todos)}'][data-unread]", visible: :all
  end

  test "a call that is on in a room shows on its desktop" do
    room = tools(:my_room)
    sleep 0.5

    press "2"
    visit workspace_path(open: tool_path(room))
    wait_for_stimulus "workspace"
    press "1"
    sleep 0.5
    ActionCable.server.broadcast("notifications:#{users(:one).id}", { type: "room_activity", tool_id: room.id, active: true })

    assert_selector ".workspace-desk[data-desk='2'] .workspace-desk-tool[data-in-call]"
    assert_selector ".workspace-desk[data-desk='2'][aria-label$='A call is on in #{room.name}']"

    ActionCable.server.broadcast("notifications:#{users(:one).id}", { type: "room_activity", tool_id: room.id, active: false })
    assert_no_selector ".workspace-desk-tool[data-in-call]"
  end

  test "a desktop can be given a name, which the bar shows and the browser keeps" do
    find(".workspace-desk[data-desk='1']").hover
    within ".workspace-desk-card" do
      find("button[aria-label='Rename desktop 1']", text: /desktop 1/i).click
      field = find("input[aria-label='Name of desktop 1']")
      field.send_keys("Launch", :enter)
    end
    assert_selector ".workspace-desk[data-desk='1'] .workspace-desk-name", text: "Launch"
    assert_selector ".workspace-desk[data-desk='1'][aria-label^='Desktop 1, Launch: ']"
    assert_no_selector ".workspace-desk-card input", visible: :all

    # Kept for the next time the workspace opens
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector ".workspace-desk[data-desk='1'] .workspace-desk-name", text: "Launch"

    # A double click on it in the bar asks too; Escape leaves the name as it was
    find(".workspace-desk[data-desk='1']").double_click
    field = find(".workspace-desk-card input[aria-label='Name of desktop 1']")
    assert_equal "Launch", field.value
    field.send_keys("ed", :escape)
    assert_no_selector ".workspace-desk-card input", visible: :all
    assert_selector ".workspace-desk[data-desk='1'] .workspace-desk-name", text: /\ALaunch\z/

    # From the menu's search, for the desktop you are on. An empty name makes it a number again.
    find(".workspace-bar-btn[aria-label='Menu']").click
    within MENU_SEARCH do
      input = find("input[data-command-palette-target='input']")
      input.set("rename")
      assert_selector ".command-palette-item.selected", text: "Rename this desktop"
      input.send_keys(:enter)
    end
    field = find(".workspace-desk-card input[aria-label='Name of desktop 1']")
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "the keyboard isn't in the name" unless page.evaluate_script("document.activeElement.matches(\"input[aria-label='Name of desktop 1']\")")
    end
    field.send_keys([ mac? ? :meta : :control, "a" ], :backspace, :enter)
    assert_no_selector ".workspace-desk-name"
    assert_selector ".workspace-desk[data-desk='1'][aria-label^='Desktop 1: ']"
  end

  test "a desktop with a name stays in the bar while nothing is open on it" do
    press "3"
    assert_selector ".workspace-desk[data-desk='3'][aria-current='true']"
    find(".workspace-desk[data-desk='3']").double_click
    find(".workspace-desk-card input[aria-label='Name of desktop 3']").send_keys("Later", :enter)
    press "1"
    assert_selector ".workspace-desk[data-desk='3'] .workspace-desk-name", text: "Later"
    assert_selector ".workspace-desk[data-desk='3'][aria-label='Desktop 3, Later, nothing open']"
  end

  test "the desktops in the bar show which tools are on them" do
    launch @files
    assert_selector ".workspace-desk[aria-current='true'] .workspace-desk-icon", count: 2

    press "2", shift: true
    assert_selector ".workspace-desk[aria-current='true']", text: "2"
    assert_selector ".workspace-desk[aria-current='true'] .workspace-desk-icon", count: 1
    assert_selector ".workspace-desk[aria-label='Desktop 1: #{@board.name}']"
  end

  test "plus and minus give the tile more of the room, or less" do
    launch @files
    board, files = tiles
    assert_in_delta board[:width], files[:width], 2

    press "="
    assert_operator tiles[1][:width], :>, files[:width]

    press "-"
    press "-"
    assert_operator tiles[1][:width], :<, files[:width]
  end

  test "a tile trades places with the one beside it" do
    launch @files

    press :arrow_left, shift: true

    board, files = tiles
    assert files[:focused]
    assert_operator files[:left], :<, board[:left]
    within_tile(1) { assert_selector "h1", text: @files.name }
  end

  test "another desktop has its own tiles, and the ones left behind stay as they were" do
    within_tile(0) { page.execute_script("window.stillHere = true") }

    press "2"
    assert_text "Nothing open on this desktop"
    launch @files
    assert_equal 1, tiles.size
    within_tile(0) { assert_selector "h1", text: @files.name }

    press "1"
    assert_equal 1, tiles.size
    within_tile(0) do
      assert_selector "h1", text: @board.name
      assert page.evaluate_script("window.stillHere"), "the tile on the other desktop was loaded again"
    end
    assert_selector ".workspace-desk[aria-current='true']", text: "1"
  end

  test "the tiles are back after a reload" do
    launch @files

    visit workspace_path
    wait_for_stimulus "workspace"

    assert_equal 2, tiles.size
    within_tile(0) { assert_selector "h1", text: @board.name }
    within_tile(1) { assert_selector "h1", text: @files.name }
  end

  test "the arrangement is this person's, not this browser's: another browser opens with it" do
    launch @files
    find(".workspace-desk[data-desk='1']").double_click
    find(".workspace-desk-card input[aria-label='Name of desktop 1']").send_keys("Launch", :enter)
    press "3"
    launch @todos, on_new_desktop: true
    assert_kept { |state| state["tiles"].size == 3 && state["desk"] == 3 }

    elsewhere do
      assert_selector ".workspace-desk[data-desk='3'][aria-current='true']"
      within_tile(0) { assert_selector "h1", text: @todos.name }
      assert_selector ".workspace-desk[data-desk='1'] .workspace-desk-name", text: "Launch"

      press "1"
      assert_equal 2, tiles.size
      # The tiles slide in from the side, and are out of sight for a moment
      assert_no_selector ".workspace-tile[data-sliding]"
      within_tile(0) { assert_selector "h1", text: @board.name }
      within_tile(1) { assert_selector "h1", text: @files.name }
    end
  end

  test "what one browser does with the tiles, the other takes over while it is open" do
    assert_kept { |state| state["tiles"].size == 1 }
    elsewhere { assert_equal 1, tiles.size }

    launch @files
    elsewhere do
      assert_selector SHOWING_TILE, count: 2
      within_tile(1) { assert_selector "h1", text: @files.name }

      launch @todos
    end

    assert_selector SHOWING_TILE, count: 3
    within_tile(2) { assert_selector "h1", text: @todos.name }
    # Told to whoever can't see it happen
    assert_selector ".workspace [role='status']", text: "Arranged as in your other window", visible: :all

    # The tile you are on closes here, and there
    press "w"
    assert_selector SHOWING_TILE, count: 2
    elsewhere do
      assert_selector SHOWING_TILE, count: 2
      within_tile(1) { assert_selector "h1", text: @files.name }
    end
  end

  test "a tile goes along to the page the other browser took it to" do
    docs = tools(:my_docs)
    document = docs_documents(:meeting_notes)
    launch docs
    elsewhere { within_tile(1) { assert_selector "h1", text: docs.name } }

    within_tile(1) { click_on document.title }
    within_tile(1) { assert_selector "h1", text: document.title }

    elsewhere { within_tile(1) { assert_selector "h1", text: document.title } }
  end

  test "a browser nobody looks at takes over what is kept when it is looked at again" do
    assert_kept { |state| state["tiles"].size == 1 }
    elsewhere { look_away }

    launch @files
    assert_kept { |state| state["tiles"].size == 2 }

    elsewhere do
      assert_selector SHOWING_TILE, count: 1
      look_again
      assert_selector SHOWING_TILE, count: 2
      within_tile(1) { assert_selector "h1", text: @files.name }
    end
  end

  test "two browsers that each changed the arrangement both keep what they did" do
    assert_kept { |state| state["tiles"].size == 1 }
    # A browser that heard nothing of what happened since (asleep, no network)
    elsewhere { look_away }
    launch @files
    assert_kept { |state| state["tiles"].size == 2 }

    elsewhere do
      launch @todos, new_tile: false

      # Refused as it was, and done again on what is kept
      assert_selector ".workspace [role='status']", text: "Arranged as in your other window", visible: :all
      assert_selector SHOWING_TILE, count: 3
      within_tile(1) { assert_selector "h1", text: @todos.name }
      within_tile(2) { assert_selector "h1", text: @files.name }
    end
    assert_kept { |state| state["tiles"].size == 3 }
    assert_selector SHOWING_TILE, count: 3
    within_tile(2) { assert_selector "h1", text: @todos.name }
  end

  test "a tile with an unsent mail in it stays when the other browser closes it" do
    mail = tools(:my_mail)
    visit workspace_path(open: new_tool_mail_path(mail))
    wait_for_stimulus "workspace"
    within_tile(1) do
      find("rhino-editor [contenteditable]").send_keys("Not sent yet")
      assert_selector "rhino-editor [contenteditable]", text: "Not sent yet"
    end
    assert_kept { |state| state["tiles"].size == 2 }

    elsewhere do
      # Nothing was written there: it closes without a question
      assert_selector SHOWING_TILE, count: 2
      press :arrow_right
      assert_focused 1
      press "w"
      within_tile(0) { assert_selector "h1", text: @board.name }
      assert_selector SHOWING_TILE, count: 1

      # And is back, because here it couldn't go
      assert_selector SHOWING_TILE, count: 2
    end
    assert_selector SHOWING_TILE, count: 2
    within_tile(1) { assert_selector "rhino-editor [contenteditable]", text: "Not sent yet" }
  end

  test "a tool picked from the menu opens as a tile" do
    find(".workspace-bar-btn[aria-label='Menu']").click
    find("[data-sidebar-tool-link]", text: @todos.name).click

    within_tile(1) { assert_selector "h1", text: @todos.name }
    assert_current_path workspace_path
    assert_no_selector ".sidebar.open"
  end

  test "a tool renamed from the menu is renamed everywhere at once: its tile, the menu, the bar" do
    launch @files
    page.execute_script("window.stillTheSamePage = true")
    within_tile(1) { page.execute_script("window.stillThere = true") }

    find(".workspace-bar-btn[aria-label='Menu']").click
    find(".sidebar-tool-menu-btn[data-tool-id='#{@board.id}']", visible: :all).click
    within "dialog#edit-tool-modal[open]" do
      fill_in "Name", with: "Roadmap"
      click_on "Save Changes"
    end

    within_tile(0) { assert_selector "h1", text: "Roadmap" }
    assert_selector "[data-sidebar-tool-link][data-tool-name='Roadmap']", visible: :all
    assert_selector ".workspace-desk[aria-label='Desktop 1: Roadmap, #{@files.name}']"
    assert_no_selector "dialog#edit-tool-modal[open]"
    # Nothing was loaded again but the tile of the tool that changed, and you stayed where you were
    assert page.evaluate_script("window.stillTheSamePage")
    within_tile(1) { assert page.evaluate_script("window.stillThere"), "the other tile was loaded again" }
    assert_equal 2, tiles.size
    assert_focused 1
  end

  test "a tool made here opens as a tile, and the menu and the launcher know it at once" do
    find(".workspace-bar-btn[aria-label='Menu']").click
    find(".sidebar-logo-btn", match: :first).click
    click_on "Add Tool"
    within "dialog#new-tool-modal[open]" do
      find("label", text: "Todos").click
      fill_in "Name", with: "Groceries"
      click_on "Create"
    end

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 2
    within_tile(1) { assert_selector "h1", text: "Groceries" }
    assert_current_path workspace_path
    assert_selector "[data-sidebar-tool-link]", text: "Groceries", visible: :all
    assert_selector ".command-palette-item", text: "Groceries", visible: :all
    # The tiles were left alone while the page around them was drawn again
    within_tile(0) { assert_selector "h1", text: @board.name }
  end

  test "a tile whose tool is deleted goes" do
    launch @files
    @files.destroy!

    page.execute_script("Turbo.visit(location.href, { action: 'replace' })")

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 1
    within_tile(0) { assert_selector "h1", text: @board.name }
  end

  test "a tool opened by its address becomes a tile" do
    visit tool_todo_path(@todos)

    assert_current_path workspace_path
    assert_equal 2, tiles.size
    within_tile(1) { assert_selector "h1", text: @todos.name }
    assert_focused 1
  end

  test "a window too narrow for tiles shows the tool you were on, the usual way" do
    launch @files
    page.driver.browser.manage.window.resize_to(900, 900)

    visit workspace_path

    assert_current_path tool_files_path(@files), ignore_query: true
    assert_selector "main h1", text: @files.name
    assert_no_selector "[data-controller~='workspace']"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  private

  # Through the launcher, as a person would
  def launch(tool, new_tile: true, on_new_desktop: false)
    count = on_new_desktop ? 0 : tiles.size
    find(".workspace-bar-btn[aria-label='Menu']").click
    within MENU_SEARCH do
      input = find("input[data-command-palette-target='input']")
      input.set(tool.name)
      assert_selector ".command-palette-item.selected", text: tool.name
      input.send_keys(:enter)
    end
    assert_no_selector ".sidebar.open"
    return unless new_tile

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: count + 1
    within_tile(count) { assert_selector "h1", text: tool.name }
  end

  def mac? = page.evaluate_script("navigator.platform").match?(/Mac|iP/)

  # The same person at the workspace in another browser, which opens the first time
  def elsewhere(&block)
    using_session("elsewhere") do
      unless @elsewhere
        page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument",
          source: "navigator.serviceWorker.register = () => Promise.resolve()")
        sign_in_as users(:one)
        page.driver.browser.manage.delete_cookie("workspace")
        visit workspace_path
        wait_for_stimulus "workspace"
        @elsewhere = true
      end
      block.call
    end
  end

  # The arrangement as the server keeps it: a browser sends a change a moment after it was made
  def assert_kept(&condition)
    assert_db_change(-> { (layout = WorkspaceLayout.find_by(user: users(:one))) && condition.call(layout.state) })
  end

  # A window behind another one, a tab that isn't the one in front
  def look_away
    page.execute_script(<<~JS)
      Object.defineProperty(document, "hidden", { configurable: true, get: () => true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def look_again
    page.execute_script(<<~JS)
      delete document.hidden
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  # The keys that are the workspace's go with Alt, and on a Mac with Control and Option
  # What this page (the workspace, or the tile the test is in) has played, in order.
  # A job, a broadcast and a browser lie between the cause and the sound.
  def assert_heard_here(*names)
    page.document.synchronize(15) do
      heard = page.evaluate_script("window.heardSounds")
      raise Capybara::ExpectationNotMet, "expected to hear #{names.inspect}, heard #{heard.inspect}" unless heard == names
    end
  end

  def press(key, shift: false)
    held = mac? ? %i[control alt] : %i[alt]
    held << :shift if shift
    find("body").send_keys([ *held, key ])
  end

  # Keys to whatever has the keyboard, without moving it first
  def type_keys(*held, key)
    chain = page.driver.browser.action
    held.each { |modifier| chain.key_down(modifier) }
    chain.send_keys(key)
    held.reverse_each { |modifier| chain.key_up(modifier) }
    chain.perform
  end

  # Showing tiles in the order they were opened, with the place they have (where they
  # are going, while they still slide there)
  def tiles
    page.evaluate_script(<<~JS).map(&:symbolize_keys)
      Array.from(document.querySelectorAll(".workspace-tile:not([hidden], [data-leaving])")).map((tile) => {
        const [ left, top, width, height ] = [ "left", "top", "width", "height" ].map((side) => parseFloat(tile.style[side]))
        return { left, top, width, height, focused: tile.hasAttribute("data-focused") }
      })
    JS
  end

  def focused_index = tiles.index { |tile| tile[:focused] }

  # The focus follows a key a moment later (a tile hands the key on first)
  def assert_focused(index)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "tile #{focused_index.inspect} has the focus, not #{index}" unless focused_index == index
    end
  end

  # The frame a tile's dialog floats in, over all the tiles
  def within_float(&block)
    within_frame(find(".workspace-float iframe"), &block)
  end

  def within_tile(index, &block)
    within_frame(all(".workspace-tile:not([hidden], [data-leaving]) iframe", minimum: index + 1)[index], &block)
  end
end

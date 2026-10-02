# frozen_string_literal: true

require "application_system_test_case"

class WorkspaceTest < ApplicationSystemTestCase
  setup do
    @board = tools(:project_board)
    @files = tools(:my_files)
    @todos = tools(:my_todos)
    sign_in_as users(:one)
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
    within "dialog[data-controller~='command-palette'][open]" do
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
    within_tile(0) { page.execute_script("Turbo.visit('#{tool_board_card_path(@board, 0)}')") }

    within_tile(0) { assert_selector "h1", text: @board.name }
    assert_equal 1, tiles.size
  end

  test "the way out is there in a window that got narrow too" do
    page.driver.browser.manage.window.resize_to(900, 900)

    assert_equal 1, tiles.size
    find(".mobile-bottom-bar-item[popovertarget='sidebar-user-menu']").click
    assert_selector "button", text: "Use one tool at a time"
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
    find(".workspace-launcher").click
    within "dialog[data-controller~='command-palette'][open]" do
      assert_text "In a new tile"
      input = find("input[data-command-palette-target='input']")
      input.set(docs.name)
      assert_selector ".command-palette-item.selected", text: docs.name
      input.send_keys([ :shift, :enter ])
    end
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 3

    within_tile(2) { find("a", text: docs_documents(:meeting_notes).title).click(:alt) }
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 4
    within_tile(3) { assert_selector "h1", text: docs_documents(:meeting_notes).title }
    within_tile(2) { assert_selector "h1", text: docs.name }
  end

  test "the menu is gone through with the arrow keys, and a tool opened from it" do
    press "m"
    assert_selector ".sidebar.open"
    assert_selector "[data-sidebar-tool-link]:focus"

    type_keys :arrow_down
    opened = page.evaluate_script("document.activeElement.textContent.trim().split('\\n')[0]")
    type_keys :enter

    assert_no_selector ".sidebar.open"
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 2
    within_tile(1) { assert_selector "h1", text: opened }
  end

  test "the menu's button says it is open, keeps the tiles out of reach, and gets the keyboard back" do
    menu = find(".workspace-bar-btn[aria-label='Menu']")
    assert_equal "false", menu["aria-expanded"]

    menu.send_keys(:enter)
    assert_selector ".sidebar.open"
    assert_selector ".workspace-bar-btn[aria-label='Menu'][aria-expanded='true']"
    assert_selector "#workspace-tiles[inert]"
    assert_selector "[data-sidebar-tool-link]:focus"

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

    find(".workspace-launcher").click
    within "dialog[data-controller~='command-palette'][open]" do
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

  test "the bell in the bar opens the notifications over the tiles" do
    find(".workspace-bar-btn[aria-label='Notifications']").click

    assert_selector "#sidebar-notifications", text: "Notifications"
    type_keys :escape
    assert_no_selector "#sidebar-notifications"
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

  test "a tool picked from the menu opens as a tile" do
    find(".workspace-bar-btn[aria-label='Menu']").click
    find("[data-sidebar-tool-link]", text: @todos.name).click

    within_tile(1) { assert_selector "h1", text: @todos.name }
    assert_current_path workspace_path
    assert_no_selector ".sidebar.open"
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

  test "one tool at a time brings the sidebar back, and the workspace is a click away" do
    find(".workspace-bar-btn[popovertarget='sidebar-user-menu']").click
    click_on "Use one tool at a time"

    assert_no_selector "[data-controller~='workspace']"
    assert_selector ".sidebar"
    assert_selector "main h1"

    # And stays: a tool's address is its page
    visit tool_files_path(@files)
    assert_selector "main h1", text: @files.name
    assert_current_path tool_files_path(@files)

    find(".sidebar-user-btn").click
    click_on "Use the tiling workspace"
    assert_selector "[data-controller~='workspace']"
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
    find(".workspace-launcher").click
    within "dialog[data-controller~='command-palette'][open]" do
      input = find("input[data-command-palette-target='input']")
      input.set(tool.name)
      assert_selector ".command-palette-item.selected", text: tool.name
      input.send_keys(:enter)
    end
    assert_no_selector "dialog[data-controller~='command-palette'][open]"
    return unless new_tile

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: count + 1
    within_tile(count) { assert_selector "h1", text: tool.name }
  end

  def mac? = page.evaluate_script("navigator.platform").match?(/Mac|iP/)

  # The keys that are the workspace's go with Alt, and on a Mac with Control and Option
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

  def within_tile(index, &block)
    within_frame(all(".workspace-tile:not([hidden], [data-leaving]) iframe", minimum: index + 1)[index], &block)
  end
end

# frozen_string_literal: true

require "application_system_test_case"

# A board as a tile in the workspace's own page (workspace_controller.js#inThisPage):
# the second kind of tool to move out of its frame. What every such tile does is in
# workspace_in_page_test.rb; this is what a board has of its own.
class WorkspaceInPageBoardTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  BOARD = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @board = tools(:project_board)
    @files = tools(:my_files)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path("in-page": "todos,boards", open: tool_path(@board))
    wait_for_stimulus "workspace"
    assert_selector "#{BOARD} .tile-page h1", text: @board.name
  end

  teardown do
    page.execute_script("try { localStorage.removeItem('dobase:workspace:in-page') } catch (error) {}")
  end

  test "the board is part of the workspace's page, with its columns and cards" do
    within(BOARD) do
      assert_text "TO DO"
      assert_text cards(:first_task).title
      assert_no_selector ".sidebar", visible: :all
    end
    assert_equal 0, page.evaluate_script("window.frames.length")
  end

  test "a card is added by its key, to the column you are in" do
    find(BOARD).click
    find("#{BOARD} .tile-page").send_keys("c")
    within(BOARD) do
      find("textarea[aria-label='Card title']:focus").send_keys("Ship it", :enter)
      assert_selector "#column-#{columns(:todo).id}-cards .board-card", text: "Ship it"
    end
    assert Boards::Card.exists?(title: "Ship it", column: columns(:todo))
    assert_current_path workspace_path

    # The form went with the page that was drawn again: the keyboard is still the board's
    4.times do
      page.send_keys(:arrow_down)
      assert in_the_board?, "The keyboard went to #{where_the_keyboard_is}"
    end
  end

  test "a card's details open over the whole window, and closing leaves the board as it was" do
    card = cards(:first_task)
    open_beside @files

    within(BOARD) { find("[data-card-id='#{card.id}']").click }

    assert_selector "dialog#card-detail-modal[open]", text: card.title
    assert_no_selector ".workspace-float iframe"
    width = page.evaluate_script("document.querySelector('dialog#card-detail-modal').getBoundingClientRect().width")
    tile = page.evaluate_script("document.querySelector(#{BOARD.to_json}).getBoundingClientRect().width")
    assert_operator width, :>, tile, "The dialog is held inside its tile"

    find("dialog#card-detail-modal [aria-label='Close']").click
    assert_no_selector "dialog#card-detail-modal[open]"
    assert_selector "#{BOARD}:not([src*='card='])"
    assert_selector "#{BOARD} [data-card-id='#{card.id}']"
  end

  test "a card is dragged to another column" do
    card = cards(:first_task)
    dragged = find("#{BOARD} [data-card-id='#{card.id}']").native
    onto = find("#{BOARD} [data-card-id='#{cards(:third_task).id}']").native

    page.driver.browser.action.click_and_hold(dragged).move_by(10, 5).move_by(20, 5).move_to(onto, 0, 10).move_by(0, 5).release.perform

    assert_db_change(-> { card.reload.column_id == cards(:third_task).column_id })
    assert_no_selector "dialog[open]"
    assert_current_path workspace_path
  end

  test "a card is archived from its details, and is gone from the board" do
    card = cards(:second_task)
    within(BOARD) { find("[data-card-id='#{card.id}']").click }
    within("dialog#card-detail-modal[open]") { click_on "Archive card" }

    assert_no_selector "#{BOARD} #column-#{card.column_id}-cards > [data-card-id='#{card.id}']"
    assert_selector "#{BOARD} .tile-page h1", text: @board.name
    assert card.reload.archived?
    assert_current_path workspace_path
    assert_selector BOARD, count: 1
  end

  test "a column is added by its key, collapsed and opened again" do
    find(BOARD).click
    find("#{BOARD} .tile-page").send_keys("n")
    within "dialog#add-column-modal-#{@board.id}[open]" do
      fill_in "Column name", with: "Later"
      click_on "Add Column"
    end
    assert_selector "#{BOARD} .board-column", text: "LATER"
    assert_no_selector "dialog[open]"
    assert_current_path workspace_path

    todo = columns(:todo)
    within(BOARD) { find("[aria-label='Collapse #{todo.name} column']").click }
    assert_selector "#{BOARD} #board-column-#{todo.id}.collapsed"
    within(BOARD) { find("[aria-label='Expand #{todo.name} column']").click }
    assert_no_selector "#{BOARD} #board-column-#{todo.id}.collapsed"
  end

  test "a link to a card opens it in the tile that is there" do
    card = cards(:third_task)

    page.execute_script("Turbo.visit(arguments[0])", tool_board_path(@board, card: card.id))

    assert_selector "dialog#card-detail-modal[open]", text: card.title
    assert_selector BOARD, count: 1
    assert_current_path workspace_path
  end

  test "the filter by assignee is the board's own beside a todo list, and stays in the tile" do
    open_beside tools(:my_todos)
    assert_selector "#{TILE} > turbo-frame.tile-frame", count: 2

    board = find("#{BOARD}#tile-#{tile_id_of(@board)}")
    within(board) { click_on "All assignees" }
    within("#assignee-filter-menu-#{@board.id}:popover-open") { click_on "Unassigned" }

    assert_selector "#{BOARD}[src*='assignee=unassigned']"
    within(board) { assert_selector "h1", text: @board.name }
    assert_current_path workspace_path
  end

  test "reordering and back stay in the tile" do
    within(BOARD) { click_on "Edit" }
    assert_selector "#{BOARD} .reorder-mode"

    within(BOARD) { click_on "Done" }
    assert_no_selector "#{BOARD} .reorder-mode"
    assert_current_path workspace_path
  end

  test "the arrows go from card to card and column to column, and never out of the board" do
    open_beside @files
    find(BOARD).click
    find("#{BOARD} .tile-page").send_keys(:arrow_down)

    seen = %i[arrow_right arrow_down arrow_left arrow_up].flat_map do |arrow|
      8.times.map do
        page.send_keys(arrow)
        assert in_the_board?, "#{arrow} took the keyboard out of the board, to #{where_the_keyboard_is}"
        page.evaluate_script("document.activeElement.closest('[data-card-id]')?.dataset.cardId")
      end
    end
    assert_operator seen.compact.uniq.size, :>=, 3, "The arrows only reached #{seen.compact.uniq}"
  end

  private

  def open_beside(tool)
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(tool))
    assert_selector "#{TILE} > :is(iframe, turbo-frame)", count: 2
  end

  # The tile a tool is in, by the address of its frame
  def tile_id_of(tool)
    page.evaluate_script("document.querySelector(\"turbo-frame.tile-frame[src^='/tools/#{tool.id}'], turbo-frame.tile-frame[src*='/tools/#{tool.id}/']\").id.replace('tile-', '')")
  end

  def in_the_board?
    page.evaluate_script("Boolean(document.activeElement.closest('turbo-frame.tile-frame'))")
  end

  def where_the_keyboard_is
    page.evaluate_script("(document.activeElement.getAttribute('aria-label') || document.activeElement.className || document.activeElement.tagName).toString().slice(0, 80)")
  end
end

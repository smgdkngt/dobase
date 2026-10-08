# frozen_string_literal: true

require "application_system_test_case"

# A tile without a document of its own: a tool's page drawn into the workspace's
# page, in a <turbo-frame> (workspace_controller.js#inThisPage). Every kind of tool
# but a room is one; what they all do is tried here, on todos.
class WorkspaceInPageTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  TODOS = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @todos = tools(:my_todos)
    @room = tools(:my_room)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(@todos))
    wait_for_stimulus "workspace"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
  end

  test "todos are part of the workspace's page, and a room is a frame of its own" do
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(@room))

    assert_selector "#{TILE} > iframe", count: 1
    assert_selector TODOS, count: 1
    within(TODOS) do
      assert_no_selector ".sidebar", visible: :all
      assert_text todo_items(:pending_one).title
    end
    # One document for the room, none for the todos
    assert_equal 1, page.evaluate_script("window.frames.length")
  end

  test "a todo is ticked off, and its tile alone is drawn again" do
    item = todo_items(:pending_one)
    page.execute_script("window.pageBefore = document.querySelector('.workspace-bar')")

    within(TODOS) { find("#todo-item-#{item.id}-completion").click }

    assert_selector "#{TODOS} #todo-item-#{item.id}.todo-item-completed"
    assert item.reload.completed?
    assert_current_path workspace_path
    assert page.evaluate_script("window.pageBefore === document.querySelector('.workspace-bar')"), "The page around the tiles was replaced"
  end

  test "a todo is added from the tile, by its key too" do
    find(TODOS).click
    find("#{TODOS} .tile-page").send_keys("t")
    within(TODOS) do
      field = find("textarea[aria-label='Todo title']:focus")
      field.send_keys("Water the plants", :enter)
      assert_selector ".todo-item", text: "Water the plants"
    end
    assert Todos::Item.exists?(title: "Water the plants")
    assert_current_path workspace_path
  end

  test "a todo's details open over the whole window" do
    item = todo_items(:pending_one)
    # Beside another tile, so the todos have half the window
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(@room))
    assert_selector "#{TILE} > iframe"

    within(TODOS) { find("[aria-label='Open #{item.title}']").click }

    assert_selector "dialog#item-detail-modal[open]", text: item.title
    width = page.evaluate_script("document.querySelector('dialog#item-detail-modal').getBoundingClientRect().width")
    tile = page.evaluate_script("document.querySelector(#{TODOS.to_json}).getBoundingClientRect().width")
    assert_operator width, :>, tile, "The dialog is held inside its tile"

    find("dialog#item-detail-modal [aria-label='Close']").click
    assert_no_selector "dialog#item-detail-modal[open]"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
  end

  test "a list is added by its key, and the page around the tiles stays" do
    find(TODOS).click
    find("#{TODOS} .tile-page").send_keys("n")
    within "dialog#add-list-modal-#{@todos.id}[open]" do
      fill_in "List title", with: "Later"
      click_on "Add List"
    end

    assert_selector "#{TODOS} [data-list-id]", text: "Later"
    assert_no_selector "dialog[open]"
    assert_current_path workspace_path
    assert_selector TODOS, count: 1
  end

  test "reordering and back stay in the tile, and the window keeps its address" do
    within(TODOS) { click_on "Edit" }
    assert_selector "#{TODOS} .reorder-mode"

    within(TODOS) { click_on "Done" }
    assert_no_selector "#{TODOS} .reorder-mode"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
    assert_current_path workspace_path
  end

  test "a todo is deleted from its details, and is gone from the tile" do
    item = todo_items(:pending_two)
    within(TODOS) { find("[aria-label='Open #{item.title}']").click }
    accept_confirm_dialog do
      within("dialog#item-detail-modal[open]") { click_on "Delete item" }
    end

    assert_no_selector "#{TODOS} #todo-item-#{item.id}"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
    assert_not Todos::Item.exists?(item.id)
    assert_current_path workspace_path
  end

  test "a link to a todo opens it in the tile that is there" do
    item = todo_items(:pending_two)

    page.execute_script("Turbo.visit(arguments[0])", tool_todo_path(@todos, item: item.id))

    assert_selector "dialog#item-detail-modal[open]", text: item.title
    assert_selector TODOS, count: 1
    assert_current_path workspace_path

    find("dialog#item-detail-modal [aria-label='Close']").click
    assert_no_selector "dialog#item-detail-modal[open]"
    # Closed is closed: the tile isn't on the address that opens it any more. Once the
    # dialog has faded out, that is: its "close" comes after that, and the tile goes
    # to its own address then.
    assert_selector "#{TODOS}:not([src*='item='])"
    assert_selector TODOS, count: 1
  end

  test "the tile's keys are in the shortcuts dialog and its actions in the launcher" do
    find(TODOS).click
    find("#{TODOS} .tile-page").send_keys("?")
    within "dialog[open]" do
      assert_text "Add todo"
      assert_text "Tick the todo off"
      send_keys :escape
    end

    find(".workspace-bar-btn[aria-label='Menu']").click
    within ".sidebar.open [data-controller~='command-palette']" do
      find("input[data-command-palette-target='input']").set("add todo")
      assert_selector ".command-palette-item.selected", text: "Add todo"
      find("input[data-command-palette-target='input']").send_keys(:enter)
    end
    assert_selector "#{TODOS} textarea[aria-label='Todo title']:focus"
  end

  test "the arrows go from todo to todo, and Escape leaves the tool for its tile" do
    find(TODOS).click
    page_in_tile = find("#{TODOS} .tile-page")
    page_in_tile.send_keys(:arrow_down)
    first = page.evaluate_script("document.activeElement.closest('[data-item-id]')?.dataset.itemId")
    page.send_keys(:arrow_down)
    second = page.evaluate_script("document.activeElement.closest('[data-item-id]')?.dataset.itemId")
    assert first.present? && second.present? && first != second, "The arrows stayed on #{first.inspect}"

    page.send_keys(:escape)
    page.send_keys(:escape)
    assert_selector "#{TILE}:focus"
  end

  test "the arrows never leave the tool, whichever way they are pressed" do
    open_beside @room
    find(TODOS).click
    find("#{TODOS} .tile-page").send_keys(:arrow_down)

    %i[arrow_up arrow_left arrow_right arrow_down].each do |arrow|
      12.times do
        page.send_keys(arrow)
        assert in_the_todos?, "#{arrow} took the keyboard out of the tool, to #{where_the_keyboard_is}"
      end
    end
  end

  test "a todo ticked off by the keyboard leaves the keyboard in the tool" do
    open_beside @room
    find(TODOS).click
    box = find("#{TODOS} #todo-item-#{todo_items(:pending_one).id}-completion")
    box.send_keys(:space)
    assert_selector "#{TODOS} #todo-item-#{todo_items(:pending_one).id}.todo-item-completed"

    # Whatever the drawing again did to what had the keyboard: the next keys are the tool's
    4.times do
      page.send_keys(:arrow_down)
      assert in_the_todos?, "The keyboard went to #{where_the_keyboard_is}"
    end
    page.send_keys("t")
    assert_selector "#{TODOS} textarea[aria-label='Todo title']:focus"
  end

  test "after a todo is added the keyboard is still the tool's" do
    open_beside @room
    find(TODOS).click
    find("#{TODOS} .tile-page").send_keys("t")
    find("#{TODOS} textarea[aria-label='Todo title']:focus").send_keys("Water the plants", :enter)
    assert_selector "#{TODOS} .todo-item", text: "Water the plants"

    # The form went with the page that was drawn again, and the keyboard with it
    6.times do |press|
      page.send_keys(press < 3 ? :arrow_down : :arrow_up)
      assert in_the_todos?, "The keyboard went to #{where_the_keyboard_is}"
    end
  end

  test "the arrows reach the tile's own buttons and go through its dialog" do
    find(TODOS).click
    find("#{TODOS} .tile-page").send_keys(:arrow_down)
    reached = 6.times.map { page.send_keys(:arrow_up); where_the_keyboard_is }
    assert reached.any? { |where| where.include?("btn") }, "Up from the first todo never got to the top bar's buttons: #{reached.uniq}"

    within(TODOS) { find("[aria-label='Open #{todo_items(:pending_one).title}']").click }
    assert_selector "dialog#item-detail-modal[open] [aria-label='Close']:focus"
    in_dialog = 8.times.map do
      page.send_keys(:arrow_down)
      page.evaluate_script("Boolean(document.activeElement.closest('dialog#item-detail-modal'))") && where_the_keyboard_is
    end
    assert in_dialog.all?, "The arrows left the dialog"
    assert_operator in_dialog.uniq.size, :>, 2, "The arrows stayed on #{in_dialog.uniq}"
  end

  test "down from the bar is onto the tile, not into what is in it" do
    # (the line about tiles a first visit gets lies under the bar too)
    within(".workspace-hint") { click_on "Got it" }
    page.execute_script("document.querySelector(\".workspace-bar-btn[aria-label='Menu']\").focus()")
    page.send_keys(:arrow_down)

    assert_selector "#{TILE}:focus", wait: 2
    assert_not in_the_todos?
  end

  test "what a form has to say is said by the page around the tiles" do
    within(TODOS) do
      first("button", text: "Add item").click
      field = find("textarea[aria-label='Todo title']:focus")
      field.send_keys(" ", :enter)
    end

    assert_selector "#flash", text: "Title can't be blank"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
  end

  test "a todo is dragged to another place in its list" do
    first, second = todo_items(:pending_one), todo_items(:pending_two)
    dragged = find("#{TODOS} #todo-item-#{first.id} .todo-drag-handle", visible: :all).native
    onto = find("#{TODOS} #todo-item-#{second.id}").native

    find("#{TODOS} #todo-item-#{first.id}").hover
    page.driver.browser.action.click_and_hold(dragged).move_by(0, 10).move_by(0, 20).move_to(onto, 0, 10).move_by(0, 5).release.perform

    assert_db_change -> { second.reload.position < first.reload.position }
  end

  test "someone else in the tool shows up in the tile" do
    tools(:my_todos).collaborators.create!(user: users(:two), role: "collaborator")
    assert_no_selector "#{TODOS} .presence-facepile .avatar"

    using_session("colleague") do
      sign_in_as(users(:two))
      page.execute_script("Turbo.visit('#{tool_todo_path(@todos)}')")
      assert_current_path tool_todo_path(@todos)
      wait_for_stimulus "presence"
    end

    assert_selector "#{TODOS} .presence-facepile .avatar", wait: 10
  end

  test "the tile is there again after a reload, and closes like any other" do
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name

    find("#{TODOS} .tile-page").hover
    within(find(TODOS).find(:xpath, "..")) { find("button[title^='Close this tile']").click }
    assert_no_selector TODOS
  end

  private

  def open_beside(tool)
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(tool))
    assert_selector "#{TILE} > iframe"
  end

  def in_the_todos?
    page.evaluate_script("Boolean(document.activeElement.closest('turbo-frame.tile-frame'))")
  end

  def where_the_keyboard_is
    page.evaluate_script("(document.activeElement.getAttribute('aria-label') || document.activeElement.className || document.activeElement.tagName).toString().slice(0, 80)")
  end

  # The app's own confirmation dialog (shared/turbo_confirm_dialog)
  def accept_confirm_dialog
    yield
    find("dialog#turbo-confirm-dialog[open] button[value='confirm']").click
  end
end

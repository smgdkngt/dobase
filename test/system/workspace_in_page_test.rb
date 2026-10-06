# frozen_string_literal: true

require "application_system_test_case"

# The trial of a tile without a document of its own: a tool's page drawn into the
# workspace's page, in a <turbo-frame> (workspace_controller.js#inThisPage). Switched
# on per browser, for todos.
class WorkspaceInPageTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  TODOS = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @todos = tools(:my_todos)
    @files = tools(:my_files)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path("in-page": "todos", open: tool_path(@todos))
    wait_for_stimulus "workspace"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
  end

  teardown do
    page.execute_script("try { localStorage.removeItem('dobase:workspace:in-page') } catch (error) {}")
  end

  test "todos are part of the workspace's page, and any other tool is a frame of its own" do
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(@files))

    assert_selector "#{TILE} > iframe", count: 1
    assert_selector TODOS, count: 1
    within(TODOS) do
      assert_no_selector ".sidebar", visible: :all
      assert_text todo_items(:pending_one).title
    end
    # One document for the files, none for the todos
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

  test "a todo's details open over the whole window, without a page that floats" do
    item = todo_items(:pending_one)
    # Beside another tile, so the todos have half the window
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(@files))
    assert_selector "#{TILE} > iframe"

    within(TODOS) { find("[aria-label='Open #{item.title}']").click }

    assert_selector "dialog#item-detail-modal[open]", text: item.title
    assert_no_selector ".workspace-float iframe"
    width = page.evaluate_script("document.querySelector('dialog#item-detail-modal').getBoundingClientRect().width")
    tile = page.evaluate_script("document.querySelector(#{TODOS.to_json}).getBoundingClientRect().width")
    assert_operator width, :>, tile, "The dialog is held inside its tile"

    find("dialog#item-detail-modal [aria-label='Close']").click
    assert_no_selector "dialog#item-detail-modal[open]"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name
  end

  test "the tile is there again after a reload, and closes like any other" do
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{TODOS} .tile-page h1", text: @todos.name

    find("#{TODOS} .tile-page").hover
    within(find(TODOS).find(:xpath, "..")) { find("button[title^='Close this tile']").click }
    assert_no_selector TODOS
  end
end

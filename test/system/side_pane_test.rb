# frozen_string_literal: true

require "application_system_test_case"

class SidePaneTest < ApplicationSystemTestCase
  setup do
    @board = tools(:project_board)
    @files = tools(:my_files)
    @todos = tools(:my_todos)
    sign_in_as users(:one)
    visit tool_board_path(@board)
    wait_for_turbo
    wait_for_stimulus "side-pane", "#side-pane"
  end

  test "a tool opens beside the one you have open, and stays as it is while you move around" do
    open_beside @files

    within_pane do
      assert_selector "h1", text: @files.name
      assert_no_selector ".sidebar"
      # Something only this page of the pane knows
      page.execute_script("window.stillHere = true")
    end
    assert_selector "h1", text: @board.name
    assert_selector "[data-side-pane-toggle][data-tool-id='#{@files.id}'][aria-pressed='true']", visible: :all

    find("[data-sidebar-tool-link]", text: @todos.name).click
    assert_selector "main h1", text: @todos.name

    assert_selector "[data-side-pane-toggle][data-tool-id='#{@files.id}'][aria-pressed='true']", visible: :all
    within_pane do
      assert_selector "h1", text: @files.name
      assert page.evaluate_script("window.stillHere"), "the page beside was loaded again"
    end
  end

  test "moving around beside leaves the main tool where it is" do
    open_beside @files

    within_pane do
      page.execute_script("Turbo.visit('#{tool_todo_path(@todos)}')")
      assert_selector "h1", text: @todos.name
      assert_no_selector ".sidebar"
    end

    assert_selector "main h1", text: @board.name
    assert_current_path tool_board_path(@board)
    assert_selector "[data-side-pane-toggle][data-tool-id='#{@todos.id}'][aria-pressed='true']", visible: :all
  end

  test "Alt and a click opens a tool beside instead" do
    find("[data-sidebar-tool-link]", text: @files.name).click(:alt)

    within_pane { assert_selector "h1", text: @files.name }
    assert_selector "main h1", text: @board.name
    assert_current_path tool_board_path(@board)
  end

  test "it is back after a reload, and gone once it is closed" do
    open_beside @files

    visit tool_board_path(@board)
    within_pane { assert_selector "h1", text: @files.name }

    find("#side-pane button[title='Close the tool beside']").click
    assert_no_selector "#side-pane iframe", visible: :all
    assert_selector "[data-side-pane-toggle][data-tool-id='#{@files.id}'][aria-pressed='false']", visible: :all

    visit tool_board_path(@board)
    wait_for_stimulus "side-pane", "#side-pane"
    assert_no_selector "#side-pane iframe", visible: :all
  end

  test "swapping sides puts the tool beside in the middle and the other one beside" do
    open_beside @files

    find("#side-pane button[title='Swap sides']").click

    assert_selector "main h1", text: @files.name
    within_pane { assert_selector "h1", text: @board.name }
  end

  test "opening the tool that is beside from the sidebar moves it over" do
    open_beside @files

    find("[data-sidebar-tool-link]", text: @files.name).click

    assert_selector "main h1", text: @files.name
    assert_no_selector "#side-pane iframe", visible: :all
  end

  test "the button of the tool that is beside closes it again" do
    open_beside @files

    find("[data-side-pane-toggle][data-tool-id='#{@files.id}']").click

    assert_no_selector "#side-pane iframe", visible: :all
  end

  test "the main tool makes room, and the edge between the two can be moved with the keyboard" do
    width = -> { page.evaluate_script("document.querySelector('main').getBoundingClientRect().width") }
    alone = width.call
    open_beside @files

    assert_equal alone - 420, width.call

    find("#side-pane [role='separator']").send_keys(:arrow_left)

    assert_equal alone - 444, width.call
  end

  test "a window too narrow for two tools shows one, and the other is back as it was when it widens" do
    open_beside @files
    within_pane { page.execute_script("window.stillHere = true") }

    page.driver.browser.manage.window.resize_to(1100, 900)
    assert_no_selector "#side-pane"
    assert_equal "0px", page.evaluate_script("getComputedStyle(document.body).marginRight")
    assert_no_selector "[data-side-pane-toggle]"

    page.driver.browser.manage.window.resize_to(1400, 1400)
    within_pane do
      assert_selector "h1", text: @files.name
      assert page.evaluate_script("window.stillHere"), "the page beside was loaded again"
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "Alt and Enter in the command palette opens what is selected beside" do
    mod = evaluate_script("navigator.platform").match?(/Mac|iP/) ? :meta : :control
    find("body").send_keys([ mod, "k" ])
    within "dialog[data-controller~='command-palette'][open]" do
      assert_text "Open beside"
      input = find("input[data-command-palette-target='input']")
      input.set(@files.name)
      assert_selector ".command-palette-item.selected", text: @files.name
      input.send_keys([ :alt, :enter ])
    end

    within_pane { assert_selector "h1", text: @files.name }
    assert_selector "main h1", text: @board.name
  end

  test "closing a pane with an unsent mail in it asks first" do
    write_a_mail_beside

    find("#side-pane button[title='Close the tool beside']").click
    within "dialog#turbo-confirm-dialog[open]" do
      assert_text "Something there isn't finished"
      assert_selector "button[value='confirm']", text: "Close"
      click_on "Cancel"
    end
    within_pane { assert_equal "Plans", find("input[name='subject']").value }

    find("#side-pane button[title='Close the tool beside']").click
    within("dialog#turbo-confirm-dialog[open]") { click_on "Close" }
    assert_no_selector "#side-pane iframe", visible: :all
  end

  test "swapping sides leaves both where they are when the mail beside isn't to be discarded" do
    write_a_mail_beside

    dismiss_confirm("You have an unsent message. Discard it?") do
      find("#side-pane button[title='Swap sides']").click
    end

    assert_selector "main h1", text: @board.name
    assert_current_path tool_board_path(@board)
    within_pane { assert_equal "Plans", find("input[name='subject']").value }
    assert_selector "[data-side-pane-toggle][data-tool-id='#{tools(:my_mail).id}'][aria-pressed='true']", visible: :all
  end

  test "going back after a swap keeps the pane" do
    open_beside @files
    find("#side-pane button[title='Swap sides']").click
    assert_selector "main h1", text: @files.name
    within_pane { assert_selector "h1", text: @board.name }

    page.go_back

    assert_selector "main h1", text: @board.name
    assert_selector "#side-pane iframe"
  end

  test "F6 moves between the two tools, from a field too" do
    open_beside tools(:my_todos)

    find("body").send_keys(:f6)
    assert within_pane { page.evaluate_script("document.hasFocus()") }

    within_pane { find("body").send_keys(:f6) }
    assert_selector "main#main-content:focus"
  end

  test "a pane whose tool is gone closes" do
    open_beside @files
    @files.destroy!

    within_pane { page.execute_script("Turbo.visit('#{tool_files_path(@files)}')") }

    assert_no_selector "#side-pane iframe", visible: :all
  end

  test "signing out takes the pane along" do
    open_beside @files

    find(".sidebar-user-btn").click
    click_on "Sign Out"

    assert_current_path new_session_path
    assert_no_selector "#side-pane", visible: :all
  end

  private

  def write_a_mail_beside
    mail = tools(:my_mail)
    open_beside mail
    within_pane do
      page.execute_script("Turbo.visit('#{new_tool_mail_path(mail)}')")
      find("input[name='subject']").set("Plans")
    end
  end

  def open_beside(tool)
    find("[data-tool-id='#{tool.id}'] [data-sidebar-tool-link]").hover
    find("[data-side-pane-toggle][data-tool-id='#{tool.id}']").click
    within_pane { assert_selector "h1", text: tool.name }
  end

  def within_pane(&block)
    within_frame(find("#side-pane iframe"), &block)
  end
end

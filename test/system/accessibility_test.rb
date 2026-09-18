# frozen_string_literal: true

require "application_system_test_case"

class AccessibilityTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "the skip link is the first thing the keyboard reaches and moves focus to main" do
    visit tool_board_path(tools(:project_board))
    wait_for_turbo

    page.driver.browser.execute_script("document.body.focus()")
    page.send_keys(:tab)

    assert_equal "Skip to main content", focused_text
    page.send_keys(:enter)

    assert_equal "main-content", page.evaluate_script("document.activeElement.id")
  end

  test "a board card opens from the keyboard" do
    visit tool_board_path(tools(:project_board))
    wait_for_turbo
    wait_for_stimulus("board")

    card = find("[data-card-id]", text: "First task")
    assert_equal "button", card[:role]

    card.send_keys(:enter)

    assert_selector "#card-detail-modal[open]"
    assert_selector "#card-detail-modal", text: "First task"
  end

  test "closing a dialog returns focus to what opened it" do
    visit tool_board_path(tools(:project_board))
    wait_for_turbo
    wait_for_stimulus("board")

    find("button", text: "Add Column").click
    assert_selector "#add-column-modal[open]"

    find("#add-column-modal button[aria-label='Close']").click
    assert_no_selector "#add-column-modal[open]"

    assert_match(/add column/i, focused_text)
  end

  test "icon-only controls on the board announce a name" do
    visit tool_board_path(tools(:project_board))
    wait_for_turbo

    # Every control the page renders can be reached by name rather than by icon.
    assert_selector "button[aria-label='Collapse To Do column']"
    assert_selector "aside.sidebar button[aria-label^='Settings for']", visible: :all, match: :first
  end

  test "a file tile is focusable and opens on Enter" do
    tool = tools(:my_files)
    visit tool_files_path(tool)
    wait_for_turbo
    wait_for_stimulus("files")

    tile = find("[data-item-type='folder']", match: :first)
    assert_equal "0", tile[:tabindex]

    tile.send_keys(:enter)
    wait_for_turbo

    assert_current_path(/folder_id=/)
  end

  private

  def focused_text
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.activeElement
        if (!element) return ""
        return (element.getAttribute("aria-label") || element.textContent || "").trim()
      })()
    JS
  end
end

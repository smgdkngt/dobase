# frozen_string_literal: true

require "application_system_test_case"

class CommandPaletteTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "the Search action focuses the mail search box instead of doing nothing" do
    visit tool_mails_path(tools(:my_mail))
    wait_for_turbo

    find(".sidebar-jump-pill").click
    within("dialog[data-controller='command-palette']") { find("button[data-hotkey-trigger='/']").click }
    sleep 0.3

    focused = page.evaluate_script("document.activeElement === document.querySelector('input[name=q]')")
    assert focused, "expected the mail search input to be focused"
  end

  test "filtering to only tools hides the empty Actions section header" do
    visit tool_mails_path(tools(:my_mail))
    wait_for_turbo

    find(".sidebar-jump-pill").click
    within("dialog[data-controller='command-palette']") do
      assert_selector "[data-section='action']", text: /actions/i
      fill_in "Jump to a tool, or search everything...", with: "files"
      assert_no_selector "[data-section='action']", text: /actions/i
      assert_selector "[data-section='tool']", text: /tools/i
    end
  end

  test "typing searches every tool, and Enter opens what was found" do
    visit tool_mails_path(tools(:my_mail))
    wait_for_turbo

    find(".sidebar-jump-pill").click
    within("dialog[data-controller='command-palette']") do
      fill_in "Jump to a tool, or search everything...", with: "First task"
      assert_selector "[data-search-result]", text: "First task"
      find("input[data-command-palette-target='input']").send_keys(:enter)
    end

    assert_current_path tool_board_path(tools(:project_board)), ignore_query: true
    assert_selector "dialog[open] h2", text: "First task"
  end
end

# frozen_string_literal: true

require "application_system_test_case"

class TryTheDemoTest < ApplicationSystemTestCase
  setup do
    create_demo_tool_types
    @previous_demo_mode, ENV["DEMO_MODE"] = ENV["DEMO_MODE"], "true"
  end

  teardown { ENV["DEMO_MODE"] = @previous_demo_mode }

  test "a visitor tries the demo from the sign-in page" do
    visit new_session_path
    assert_text "No account needed. Everything is removed after a day."

    click_on "Try the demo"

    assert_selector ".sidebar", wait: 15
    assert_text "Product Launch"
    assert_text "Write press release for launch day"
    within ".demo-banner" do
      assert_text "You're trying the Dobase demo."
      assert_link "Get Dobase", href: "https://github.com/smgdkngt/dobase"
    end
    assert_equal 1, Demo.visitors.count
  end

  test "inviting someone says it's switched off, and the settings stay open" do
    visit new_session_path
    click_on "Try the demo"
    assert_selector ".sidebar", wait: 15
    board = Demo.visitors.last.owned_tools.find_by!(name: "Product Launch")

    wait_for_stimulus "sidebar"
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{board.id}']", visible: :all).execute_script("this.click()")
    within "dialog#edit-tool-modal[open]" do
      find("button[data-tab='collaborators']").click
      find("input[aria-label='Collaborator email address']").fill_in with: "friend@example.com"
      click_on "Add"
    end

    assert_selector "#flash", text: "That's switched off in the demo."
    assert_selector "dialog#edit-tool-modal[open]"
    assert_not board.invitations.exists?
  end
end

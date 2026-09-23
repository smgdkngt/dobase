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

  test "a visitor asks a friend over as Marcus, and they chat live" do
    visit new_session_path
    click_on "Try the demo"
    assert_selector ".sidebar", wait: 15
    visitor = Demo.visitors.last
    chat = visitor.owned_tools.find_by!(name: "Team Chat")

    within(".demo-banner") { click_on "Try it together" }
    link = within("#demo-together:popover-open") do
      assert_text "see each other type, chat and call live"
      assert_selector ".demo-together-person", count: 3
      within(".demo-together-person", text: "Marcus Rivera") do
        click_on "Copy link"
        assert_button "Copied!"
        find("input[type=hidden]", visible: :hidden).value
      end
    end
    page.execute_script("Turbo.visit('#{tool_chat_path(chat)}')")
    assert_current_path tool_chat_path(chat)
    wait_for_stimulus "chat"

    using_session("friend") do
      visit link
      assert_text "Join Moonshot Snacks"
      assert_text "open the link in a private window"
      click_on "Join as Marcus"

      assert_current_path tool_chat_path(chat), wait: 15
      wait_for_stimulus "chat"
      # Marcus sees the visitor here, and they see him
      assert_selector ".presence-face[aria-label='Guest Visitor is here']"
      within(".demo-banner") { click_on "Try it together" }
      within("#demo-together:popover-open") do
        assert_selector ".demo-together-name", count: 2
        assert_no_text "Guest Visitor"
      end
      find("body").send_keys(:escape)

      fill_in_editor "Hello from the other window"
      find("form.chat-form button[type=submit], button[type=submit][title='Send message']", match: :first).click
      assert_selector "#chat_messages", text: "Hello from the other window"
    end

    assert_selector ".presence-face[aria-label='Marcus Rivera is here']"
    assert_selector "#chat_messages", text: "Hello from the other window"
  end

  private

  def fill_in_editor(text)
    editable = find("rhino-editor .ProseMirror")
    editable.click
    editable.send_keys(text)
  end
end

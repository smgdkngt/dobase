# frozen_string_literal: true

require "application_system_test_case"

# Escape closes one thing: whatever is on top.
class EscapeKeyTest < ApplicationSystemTestCase
  setup { sign_in_as users(:one) }

  test "Escape on the list of people to mention closes the list, not the card and its unsent comment" do
    # Mentions need someone else to suggest: the shared board has an owner and a collaborator
    column = Boards::Column.create!(board: boards(:shared), name: "To Do", position: 0)
    card = Boards::Card.create!(column: column, title: "Mention test card", position: 0)
    visit tool_board_path(tools(:shared_board))
    wait_for_turbo
    wait_for_stimulus "board"
    wait_for_stimulus "keyboard-shortcuts"
    find("[data-card-id='#{card.id}']").click
    assert_selector "dialog[open] [data-controller='board-card']", wait: 10

    editable = find("dialog[open] rhino-editor .ProseMirror")
    editable.click
    editable.send_keys("Shall we ask @")
    assert_selector "dialog[open] .mention-suggestion"

    editable.send_keys(:escape)

    assert_no_selector ".mention-suggestion"
    assert_selector "dialog[open] h2", text: "Mention test card"
    assert_selector "dialog[open] rhino-editor .ProseMirror", text: "Shall we ask @"
  end

  test "Escape on the command palette over an open card closes the palette, and the next one the card" do
    visit tool_board_path(tools(:project_board), card: cards(:first_task).id)
    assert_selector "dialog[open] h2", text: "First task"
    wait_for_stimulus "keyboard-shortcuts"
    wait_for_stimulus "hotkey", "[data-hotkey='Mod+k']"

    mod = evaluate_script("navigator.platform").match?(/Mac|iP/) ? :meta : :control
    find("dialog[open]").send_keys([ mod, "k" ])
    assert_selector "dialog[data-controller='command-palette'][open]"

    find("input[data-command-palette-target='input']").send_keys(:escape)
    assert_no_selector "dialog[data-controller='command-palette'][open]"
    assert_selector "dialog[open] h2", text: "First task"

    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
  end

  test "Escape closes a dialog on a page with an Escape shortcut of its own, and leaves the page as it was" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(tools(:my_mail), message)
    assert_text message.body_plain
    wait_for_stimulus "sidebar"
    wait_for_stimulus "keyboard-shortcuts"
    wait_for_stimulus "mail-keyboard"

    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{tools(:my_mail).id}']", visible: :all).execute_script("this.click()")
    assert_selector "dialog#edit-tool-modal[open]"

    find("dialog#edit-tool-modal[open]").send_keys(:escape)

    assert_no_selector "dialog[open]"
    # Escape on the mail page itself leaves the open message; it didn't get the key
    assert_current_path tool_mail_path(tools(:my_mail), message), ignore_query: true
    assert_text message.body_plain
  end
end

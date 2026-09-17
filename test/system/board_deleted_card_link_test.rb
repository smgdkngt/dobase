# frozen_string_literal: true

require "application_system_test_case"

class BoardDeletedCardLinkTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "a link to a deleted card shows a message instead of nesting copies of the app" do
    tool = tools(:project_board)
    visit tool_board_path(tool)
    wait_for_turbo
    wait_for_stimulus "board"

    visit tool_board_path(tool, card: 999_999)
    wait_for_turbo
    sleep 1 # give any (bugged) repeat fetch loop a moment to run

    assert_equal 1, page.all("aside.sidebar", visible: :all).size
    assert_text "This card no longer exists."
    assert_no_selector "[data-board-target='cardModal'] [data-board-target='cardModal']"

    # The bad ?card= param must not linger and cause the same fetch again
    assert_no_match(/card=999999/, current_url)
  end

  test "the @-mention list is appended inside the open card dialog, not under it" do
    # project_board only has the one owner as a collaborator — mentions need
    # someone else to suggest, so use shared_board (owner + collaborator).
    tool = tools(:shared_board)
    column = Boards::Column.create!(board: boards(:shared), name: "To Do", position: 0)
    card = Boards::Card.create!(column: column, title: "Mention test card", position: 0)
    visit tool_board_path(tool)
    wait_for_turbo
    wait_for_stimulus "board"
    find("[data-card-id='#{card.id}']").click
    assert_selector "dialog[open] [data-controller='board-card']", wait: 10

    # The editable region is a plain contenteditable div slotted (light DOM)
    # into the rhino-editor custom element — find and type into it directly,
    # like a real user would, so the suggestion plugin sees genuine input.
    editable = find("dialog[open] rhino-editor .ProseMirror")
    editable.click
    editable.send_keys("@")

    assert_selector "dialog[open] .mention-suggestion", wait: 5
    # Appended inside the open dialog (top layer), not document.body, so it
    # actually renders above the dialog instead of hiding underneath it.
    within("dialog[open]") { assert_selector ".mention-suggestion" }
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end

# frozen_string_literal: true

require "application_system_test_case"

class BoardsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:project_board)
    sign_in_as(@user)
  end

  test "viewing the board shows columns and cards" do
    visit tool_board_path(@tool)

    # Column names render uppercase via CSS
    assert_text "TO DO"
    assert_text "IN PROGRESS"
    assert_text "DONE"
    assert_text "First task"
    assert_text "Second task"
    assert_text "Third task"
  end

  test "entering and exiting reorder mode" do
    visit tool_board_path(@tool)

    click_on "Edit"

    assert_current_path tool_board_path(@tool, reorder: 1)
    assert_selector "a", text: "Done"

    click_on "Done"

    assert_current_path tool_board_path(@tool)
  end

  test "adding a new column" do
    visit tool_board_path(@tool)

    click_on "Add Column"
    assert_selector "dialog#add-column-modal[open]", wait: 5

    within "dialog#add-column-modal" do
      fill_in "Column name", with: "New Column Name"
      click_on "Add Column"
    end

    assert_no_selector "dialog[open]", wait: 5

    # Column names render uppercase via CSS
    assert_text "NEW COLUMN NAME"
  end

  test "the comment box shows its own placeholder" do
    visit tool_board_path(@tool)
    open_card(cards(:first_task))

    within "dialog[open]" do
      assert_selector ".rich-text-input [data-placeholder='Write a comment...']"
    end
  end

  test "opening card detail dialog" do
    visit tool_board_path(@tool)
    open_card(cards(:first_task))

    within "dialog[open]" do
      assert_text "First task"
      assert_text "Description" # Section header
    end
  end

  test "editing card title inline" do
    visit tool_board_path(@tool)
    card = cards(:first_task)
    open_card(card)

    within "dialog[open]" do
      find("[data-board-card-target='titleDisplay']").click
      title_input = find("[data-board-card-target='titleInput']")
      title_input.fill_in with: "Updated Title"
      title_input.native.send_keys(:return)

      sleep 0.5
    end

    assert_equal "Updated Title", card.reload.title
  end

  test "closing card dialog" do
    visit tool_board_path(@tool)
    open_card(cards(:first_task))

    within "dialog[open]" do
      assert_text "First task"
      find("[title='Close']").click
    end

    assert_no_selector "dialog[open]"
  end

  test "deleting a card" do
    visit tool_board_path(@tool)
    card = cards(:first_task)
    open_card(card)

    within "dialog#card-detail-modal" do
      click_on "Delete card"
    end

    # Custom turbo confirm dialog
    within "dialog#turbo-confirm-dialog" do
      find("button[value='confirm']").click
    end

    assert_no_text "First task", wait: 5
    assert_raises(ActiveRecord::RecordNotFound) { card.reload }
  end

  test "adding a new card" do
    visit tool_board_path(@tool)

    within ".board-column", match: :first do
      click_on "Add card"

      title_input = find("textarea[name='card[title]']")
      title_input.fill_in with: "My New Card"
      title_input.native.send_keys(:return)
    end

    assert_text "My New Card"
    assert Boards::Card.exists?(title: "My New Card")
  end

  private

  def open_card(card)
    wait_for_turbo
    wait_for_stimulus "board"
    find("[data-card-id='#{card.id}']").click
    # The card's details are fetched before the dialog opens
    assert_selector "dialog[open] [data-controller='board-card']", wait: 10
  end

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end

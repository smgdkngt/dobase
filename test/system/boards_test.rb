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

    assert_text "To Do"
    assert_text "In Progress"
    assert_text "Done"
    assert_text "First task"
    assert_text "Second task"
    assert_text "Third task"
  end

  test "entering and exiting reorder mode" do
    visit tool_board_path(@tool)

    # Click reorder button
    click_on "Reorder"

    # URL should have reorder param
    assert_current_path tool_board_path(@tool, reorder: 1)

    # Done button should be visible
    assert_selector "a", text: "Done"

    # Click done to exit
    click_on "Done"

    # URL should not have reorder param
    assert_current_path tool_board_path(@tool)
  end

  test "adding a new column" do
    visit tool_board_path(@tool)

    accept_prompt(with: "New Column Name") do
      click_on "Add Column"
    end

    # Column should appear
    assert_text "New Column Name"
  end

  test "opening card detail dialog" do
    visit tool_board_path(@tool)

    # Click on a card
    find("[data-card-id='#{cards(:first_task).id}']").click

    # Dialog should open with card details
    within "dialog[open]" do
      assert_text "First task"
      assert_text "Description of first task"
    end
  end

  test "editing card title inline" do
    visit tool_board_path(@tool)
    card = cards(:first_task)

    # Open card dialog
    find("[data-card-id='#{card.id}']").click

    within "dialog[open]" do
      # Edit the title
      title_element = find(".card-detail-title")
      title_element.set("Updated Title")
      title_element.native.send_keys(:tab) # Blur to save

      sleep 0.5 # Wait for save
    end

    # Verify saved
    assert_equal "Updated Title", card.reload.title
  end

  test "editing card description inline" do
    visit tool_board_path(@tool)
    card = cards(:first_task)

    # Open card dialog
    find("[data-card-id='#{card.id}']").click

    within "dialog[open]" do
      # Edit the description
      desc_element = find(".card-detail-description")
      desc_element.set("Updated description")
      desc_element.native.send_keys(:tab) # Blur to save

      sleep 0.5 # Wait for save
    end

    # Verify saved
    assert_equal "Updated description", card.reload.description
  end

  test "changing card color" do
    visit tool_board_path(@tool)
    card = cards(:first_task)

    # Open card dialog
    find("[data-card-id='#{card.id}']").click

    within "dialog[open]" do
      # Find and hover over the color chip to reveal dropdown
      color_chip = find(".card-detail-chip", match: :first)
      color_chip.hover

      # Click on the red color option
      find("[data-color='red']").click

      sleep 0.5 # Wait for save
    end

    # Verify saved
    assert_equal "red", card.reload.color
  end

  test "setting card due date" do
    visit tool_board_path(@tool)
    card = cards(:first_task)
    tomorrow = Date.tomorrow

    # Open card dialog
    find("[data-card-id='#{card.id}']").click

    within "dialog[open]" do
      # Find the date input and set value
      date_input = find("input[type='date']", visible: :all)
      date_input.set(tomorrow.to_s)

      sleep 0.5 # Wait for save
    end

    # Verify saved
    assert_equal tomorrow, card.reload.due_date
  end

  test "closing card dialog" do
    visit tool_board_path(@tool)

    # Open card dialog
    find("[data-card-id='#{cards(:first_task).id}']").click

    within "dialog[open]" do
      assert_text "First task"
      # Click close button
      find("[title='Close']").click
    end

    # Dialog should be closed
    assert_no_selector "dialog[open]"
  end

  test "deleting a card" do
    visit tool_board_path(@tool)
    card = cards(:first_task)

    # Open card dialog
    find("[data-card-id='#{card.id}']").click

    accept_confirm do
      within "dialog[open]" do
        click_on "Delete card"
      end
    end

    # Card should be gone
    assert_no_text "First task"
    assert_raises(ActiveRecord::RecordNotFound) { card.reload }
  end

  test "adding a new card" do
    visit tool_board_path(@tool)

    # Find and click the add card button for the first column
    within ".board-column", match: :first do
      click_on "Add a card"

      # Fill in the card title
      fill_in placeholder: "Enter a title for this card...", with: "My New Card"

      # Submit with Enter
      find("textarea").native.send_keys(:return)
    end

    # Card should appear
    assert_text "My New Card"
    assert Boards::Card.exists?(title: "My New Card")
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

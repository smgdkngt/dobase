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

  test "a card moves to another column from its own dialog, without dragging" do
    card = cards(:first_task)
    visit tool_board_path(@tool, card: card.id)
    assert_selector "dialog[open] h2", text: "First task"

    within("dialog[open]") { select "Done", from: "Column" }

    # The dialog shows the card again, now in Done
    within("dialog[open]") do
      assert_text "in Done"
      assert_selector "h2", text: "First task"
    end
    assert_equal columns(:done), card.reload.column

    # And the board has caught up once the dialog closes
    within("dialog[open]") { click_on "Close" }
    within("#board-column-#{columns(:done).id}") { assert_text "First task" }
  end

  test "a message made on the page still shows after the one the page came with was dismissed" do
    rename_board_to "Roadmap"
    assert_text "Roadmap updated successfully."
    wait_for_stimulus "flash"
    find("button[aria-label='Dismiss message']").click
    assert_no_text "Roadmap updated successfully."
    wait_for_stimulus "board"

    cards(:second_task).destroy!
    find("[data-card-id='#{cards(:second_task).id}']").click

    assert_text "This card no longer exists."
  end

  test "a notice doesn't come back with the page on Back" do
    rename_board_to "Roadmap"
    assert_text "Roadmap updated successfully."

    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"
    page.go_back

    assert_selector "h1", text: "Roadmap"
    assert_no_text "Roadmap updated successfully.", wait: 0
  end

  test "a card is dragged to a new place with the mouse, right away" do
    first, second = cards(:first_task), cards(:second_task)
    visit tool_board_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sortable", "#column-#{columns(:todo).id}-cards"

    dragged = find("[data-card-id='#{first.id}']").native
    onto = find("[data-card-id='#{second.id}']").native
    page.driver.browser.action.click_and_hold(dragged).move_by(0, 10).move_by(0, 20).move_to(onto, 0, 10).move_by(0, 5).release.perform

    assert_db_change(-> { first.reload.position == 1 && second.reload.position == 0 })
    assert_equal [ second.id, first.id ], card_ids_in(columns(:todo))
    assert_no_selector "dialog[open]"
  end

  test "on a touch screen a swipe over a card leaves it where it is, and a held card can be dragged" do
    first, second = cards(:first_task), cards(:second_task)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    visit tool_board_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sortable", "#column-#{columns(:todo).id}-cards"

    from = centre_of("[data-card-id='#{first.id}']")
    to = centre_of("[data-card-id='#{second.id}']")
    to[:y] += 12

    # A swipe: the finger moves as soon as it is down. One command, so that a busy
    # machine can't turn it into a finger that rests first.
    page.driver.browser.execute_cdp("Input.synthesizeScrollGesture", x: from[:x], y: from[:y],
      yDistance: to[:y] - from[:y], speed: 400, gestureSourceType: "touch", preventFling: true)
    sleep 0.5
    assert_equal [ first.id, second.id ], card_ids_in(columns(:todo))
    assert_equal [ 0, 1 ], [ first.reload.position, second.reload.position ]

    # Holding the card first picks it up
    touch_drag(from, to, hold: 0.4)
    assert_db_change(-> { first.reload.position == 1 && second.reload.position == 0 })
    assert_equal [ second.id, first.id ], card_ids_in(columns(:todo))
  ensure
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
  end

  private

  # Saving the tool's settings comes back to the board with a notice
  def rename_board_to(name)
    visit tool_board_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sidebar"
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{@tool.id}']", visible: :all).execute_script("this.click()")
    within("dialog#edit-tool-modal[open]") do
      fill_in "Name", with: name
      click_on "Save Changes"
    end
  end

  def centre_of(selector)
    evaluate_script(<<~JS).symbolize_keys
      (() => {
        const box = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        return { x: Math.round(box.left + box.width / 2), y: Math.round(box.top + box.height / 2) }
      })()
    JS
  end

  def card_ids_in(column)
    evaluate_script("[...document.querySelectorAll('#column-#{column.id}-cards > [data-sort-id]')].map(card => Number(card.dataset.sortId))")
  end

  # A finger put down, moved in steps and lifted, the way a phone reports it
  def touch_drag(from, to, hold:)
    touch = ->(type, point = nil) do
      page.driver.browser.execute_cdp("Input.dispatchTouchEvent", type: type, touchPoints: point ? [ point ] : [])
    end
    steps = 8

    touch.call("touchStart", from)
    sleep hold
    (1..steps).each do |step|
      touch.call("touchMove", x: from[:x] + (to[:x] - from[:x]) * step / steps, y: from[:y] + (to[:y] - from[:y]) * step / steps)
      sleep 0.06
    end
    touch.call("touchEnd")
  end

  def open_card(card)
    wait_for_turbo
    wait_for_stimulus "board"
    find("[data-card-id='#{card.id}']").click
    # The card's details are fetched before the dialog opens
    assert_selector "dialog[open] [data-controller='board-card']", wait: 10
  end
end

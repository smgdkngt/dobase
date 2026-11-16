# frozen_string_literal: true

require "application_system_test_case"

# What a card's and a todo's dialog do alike (card 115/280): a long discussion opens at its
# newest comments, comments say when, the fields are at the top on a phone, a comment is
# deleted from its menu, and what was typed survives the dialog being closed. And after
# adding a card or a todo, the field is open for the next one.
class CardAndTodoDialogTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @board = tools(:project_board)
    @todos = tools(:my_todos)
    @card = cards(:first_task)
    @item = todo_items(:pending_one)
    sign_in_as(@user)
  end

  test "a card with a long discussion shows its last five comments, the earlier ones on request" do
    12.times { |n| @card.comments.create!(user: @user, body: "Card remark #{n + 1}", created_at: (20 - n).days.ago) }

    visit tool_board_path(@board)
    open_card(@card)

    within("dialog[open]") do
      assert_text "Card remark 12"
      assert_text "Card remark 8"
      assert_no_text "Card remark 7"
      assert_selector "rhino-editor"

      find("summary", text: "Show 7 earlier comments").click
      assert_text "Card remark 1"
      assert_text "Card remark 7"
      assert_selector "summary", text: "Hide earlier comments"
    end
  end

  test "a todo with a long discussion shows its last five comments, the earlier ones on request" do
    @item.comments.delete_all
    8.times { |n| @item.comments.create!(user: @user, body: "Todo remark #{n + 1}", created_at: (10 - n).days.ago) }

    visit tool_todo_path(@todos)
    open_item(@item)

    within("dialog[open]") do
      assert_text "Todo remark 8"
      assert_no_text "Todo remark 3"
      find("summary", text: "Show 3 earlier comments").click
      assert_text "Todo remark 3"
    end
  end

  test "a comment says its day and time, and the whole moment when pointed at" do
    old = @card.comments.create!(user: @user, body: "Weeks ago", created_at: Time.utc(2026, 3, 9, 14, 5))
    @card.comments.create!(user: @user, body: "Just now")

    visit tool_board_path(@board)
    open_card(@card)

    within("dialog[open] ##{ActionView::RecordIdentifier.dom_id(old)}") do
      assert_selector "time[title='Mar 9, 2026, 2:05 PM']", text: Time.zone.today.year == 2026 ? "Mar 9, 2:05 PM" : "Mar 9, 2026, 2:05 PM"
    end
    within("dialog[open]") { assert_selector "time", text: /ago\z/ }
  end

  test "a comment is deleted from its menu, with no red cross on every comment" do
    comment = @card.comments.create!(user: @user, body: "Take me back")

    visit tool_board_path(@board)
    open_card(@card)

    within("dialog[open]") do
      assert_no_selector "[title='Delete comment']"
      # The ⋯ shows where the pointer is (headless Chrome says it can't hover): pressed
      # from the keyboard, the menu takes the keyboard too
      button = find("##{ActionView::RecordIdentifier.dom_id(comment)} [title='Comment actions']", visible: :all)
      page.execute_script("arguments[0].focus(); arguments[0].click()", button)
      assert_selector "[role=menuitem]:focus", text: "Delete comment"
      find("[role=menuitem]", text: "Delete comment").click
    end
    within("dialog#turbo-confirm-dialog") { find("button[value='confirm']").click }

    within("dialog#card-detail-modal") { assert_no_text "Take me back" }
    assert_not Boards::Comment.exists?(comment.id)
  end

  test "a todo's comment is deleted from its right-click menu" do
    comment = @item.comments.create!(user: @user, body: "Not needed")

    visit tool_todo_path(@todos)
    open_item(@item)

    within("dialog[open]") do
      find("##{ActionView::RecordIdentifier.dom_id(comment)} .rich-text-content", match: :first).right_click
      find("[role=menuitem]", text: "Delete comment").click
    end
    within("dialog#turbo-confirm-dialog") { find("button[value='confirm']").click }

    within("dialog#item-detail-modal") { assert_no_text "Not needed" }
    assert_not Todos::Comment.exists?(comment.id)
  end

  test "a half-written comment on a card is there again when the card opens again, and gone once posted" do
    visit tool_board_path(@board)
    open_card(@card)
    type_in_comment_box "Half a thought"

    within("dialog[open]") { click_on "Close" }
    assert_no_selector "dialog[open]"
    open_card(@card)

    within("dialog[open]") do
      assert_selector "form[action$='/comments'] .ProseMirror", text: "Half a thought"
      click_on "Post comment"
      assert_selector ".rich-text-content", text: "Half a thought"
    end
    assert_selector "dialog[open] form[action$='/comments'] .ProseMirror", text: ""

    within("dialog[open]") { click_on "Close" }
    assert_no_selector "dialog[open]"
    open_card(@card)
    within("dialog[open]") do
      assert_selector ".rich-text-content", text: "Half a thought"
      assert_no_selector "form[action$='/comments'] .ProseMirror", text: "Half a thought"
    end
  end

  test "a half-written description on a todo opens again in its editor" do
    visit tool_todo_path(@todos)
    open_item(@item)

    within("dialog[open]") do
      find("[data-todo-item-target='descriptionDisplay']").click
      editable = find("[data-todo-item-target='descriptionEdit'] .ProseMirror")
      editable.click
      editable.send_keys("Steps to take")
      click_on "Close"
    end
    assert_no_selector "dialog[open]"
    open_item(@item)

    within("dialog[open]") do
      assert_selector "[data-todo-item-target='descriptionEdit'] .ProseMirror", text: "Steps to take", visible: true
      # Cancelled, it is gone for good
      click_on "Cancel"
    end
    within("dialog[open]") { click_on "Close" }
    assert_no_selector "dialog[open]"
    open_item(@item)
    within("dialog[open]") { assert_no_selector "[data-todo-item-target='descriptionEdit']", visible: true }
  end

  test "on a phone a card's fields are a row of chips under its title, before the discussion" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit tool_board_path(@board)
    open_card(@card)

    within("dialog[open]") do
      fields = find(".detail-modal-fields")
      comments = find("form[action$='/comments']")
      assert_operator fields.rect.y, :<, comments.rect.y, "The fields come before the discussion"
      assert_operator fields.rect.y, :<, find("h3", text: "Description").rect.y

      # Their names are for a screen reader only: the chip says what it is
      assert_operator find(".detail-field-label", text: "Column", visible: :all).rect.width, :<=, 1
      select "Done", from: "Column"
      assert_text "in Done"
    end
    assert_equal columns(:done), @card.reload.column
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "on a phone a todo's fields are at the top too" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit tool_todo_path(@todos)
    open_item(@item)

    within("dialog[open]") do
      assert_operator find(".detail-modal-fields").rect.y, :<, find("h3", text: "Description").rect.y
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "after adding a card the field is open again for the next one" do
    visit tool_board_path(@board)

    within("#board-column-#{columns(:todo).id}") do
      click_on "Add card"
      find("textarea[name='card[title]']").send_keys("First of many", :enter)
      assert_selector ".board-card", text: "First of many"
      find("textarea[name='card[title]']:focus").send_keys("Second of many", :enter)
      assert_selector ".board-card", text: "Second of many"
    end
    assert Boards::Card.exists?(title: "Second of many", column: columns(:todo))
  end

  test "after adding a todo the field is open again for the next one" do
    visit tool_todo_path(@todos)
    wait_for_stimulus "todo"

    list = todo_lists(:main)
    find("[data-todo-target='addItemBtn'][data-list-id='#{list.id}']").click
    find("textarea[data-list-id='#{list.id}']").send_keys("Buy milk", :enter)
    assert_text "Buy milk"
    find("textarea[data-list-id='#{list.id}']:focus").send_keys("Buy bread", :enter)
    assert_text "Buy bread"
    assert Todos::Item.exists?(title: "Buy bread", todo_list_id: list.id)
  end

  private

  def open_card(card)
    wait_for_turbo
    wait_for_stimulus "board"
    find("[data-card-id='#{card.id}']").click
    assert_selector "dialog[open] [data-controller='board-card']", wait: 10
  end

  def open_item(item)
    wait_for_turbo
    wait_for_stimulus "todo"
    find("[data-action~='click->todo#openItem'][data-item-id='#{item.id}']").click
    assert_selector "dialog[open] [data-controller='todo-item']", wait: 10
  end

  def type_in_comment_box(text)
    editable = find("dialog[open] form[action$='/comments'] .ProseMirror")
    editable.click
    editable.send_keys(text)
    # Kept as it is typed
    assert_selector "dialog[open] form[action$='/comments'] .ProseMirror", text: text
  end
end

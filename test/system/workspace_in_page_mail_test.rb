# frozen_string_literal: true

require "application_system_test_case"

# A mailbox as a tile in the workspace's own page (workspace_controller.js#inThisPage).
# What every such tile does is in workspace_in_page_test.rb; this is what mail has of
# its own: a conversation read beside its list or in its place, by the tile's width;
# the tile's address following what is read; and a message being written that is not
# dropped without a word.
class WorkspaceInPageMailTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  MAIL = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @tool = tools(:my_mail)
    @message = mails_messages(:inbox_unread)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(@tool))
    wait_for_stimulus "workspace"
    assert_selector "#{MAIL} .mail-list-item", text: "Welcome to Dobase"
    wait_for_stimulus "mail-keyboard"
    within(".workspace-hint") { click_on "Got it" }
  end

  test "a conversation is read beside its list, and the tile is where it is" do
    find("#{MAIL} .mail-list-item", text: "Welcome to Dobase").click

    assert_selector "#{MAIL} .mail-detail-header h1", text: "Welcome to Dobase"
    assert_selector "#{MAIL} .mail-list-item", text: "Your weekly report"
    assert_current_path workspace_path
    assert_db_change -> { WorkspaceLayout.find_by(user: users(:one))&.state.to_json.to_s.include?("/mails/#{@message.id}") }

    # The window loaded again: the tile comes back with the conversation open
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{MAIL} .mail-detail-header h1", text: "Welcome to Dobase"
    assert_selector "#{MAIL} .mail-list-item", text: "Your weekly report"
  end

  test "in a narrow tile a conversation takes the list's place, and the arrow back brings the list" do
    beside_another_tile
    assert_no_selector "#{MAIL} .mail-detail-header", visible: true

    find("#{MAIL} .mail-list-item", text: "Welcome to Dobase").click
    assert_selector "#{MAIL} .mail-detail-header h1", text: "Welcome to Dobase"
    assert_no_selector "#{MAIL} .mail-list-item", visible: true

    find("#{MAIL} .mail-detail-header > a:first-child").click
    assert_selector "#{MAIL} .mail-list-item", text: "Welcome to Dobase"
    assert_current_path workspace_path
  end

  test "an open conversation is archived, and the tile goes on" do
    find("#{MAIL} .mail-list-item", text: "Welcome to Dobase").click
    assert_selector "#{MAIL} .mail-detail-header h1", text: "Welcome to Dobase"

    find("#{MAIL} [title='Archive (e)']").click

    assert_db_change -> { @message.reload.archived? }
    assert_no_selector "#{MAIL} .mail-list-item", text: "Welcome to Dobase"
    assert_selector MAIL, count: 1
    assert_current_path workspace_path
  end

  test "j and k go through the conversations, and the tile's own keys stay its own" do
    find("#{MAIL} .tile-page").execute_script("this.focus()")
    page.send_keys("j")
    assert_selector "#{MAIL} .mail-detail-header h1"
    first = find("#{MAIL} .mail-detail-header h1").text

    page.send_keys("j")
    assert_no_selector "#{MAIL} .mail-detail-header h1", text: first
    page.send_keys("k")
    assert_selector "#{MAIL} .mail-detail-header h1", text: first
    assert_current_path workspace_path
  end

  test "a message is written in the tile, and the tile is not closed over it without asking" do
    find("#{MAIL} .tile-page").execute_script("this.focus()")
    page.send_keys("c")
    assert_selector "#{MAIL} form[data-controller~='compose']"
    wait_for_stimulus "compose"
    find("#{MAIL} input[name='subject']").set("Half a thought")

    find(MAIL).find(:xpath, "..").find("button[title^='Close this tile']", visible: :all).execute_script("this.click()")
    within("dialog#turbo-confirm-dialog[open]") do
      assert_text "unfinished work"
      click_on "Cancel"
    end
    assert_selector "#{MAIL} input[name='subject']"
    assert_equal "Half a thought", find("#{MAIL} input[name='subject']").value
  end

  test "a message written in the tile is sent, and its conversation opens there" do
    find("#{MAIL} .tile-page").execute_script("this.focus()")
    page.send_keys("c")
    wait_for_stimulus "recipients"

    deliveries = capture_smtp_deliveries do
      find("#{MAIL} input[data-compose-target='to']").set("ann@example.com")
      find("#{MAIL} input[name='subject']").set("Hello from a tile")
      perform_enqueued_jobs(only: SendMailJob) do
        within(MAIL) { click_on "Send" }
        assert_selector "#{MAIL} .mail-detail-header h1", text: "Hello from a tile"
      end
    end

    assert_equal [ "ann@example.com" ], deliveries.sole[:recipients]
    assert_selector MAIL, count: 1
    assert_current_path workspace_path
  end

  test "the arrows go through the conversations and never out of the mailbox" do
    find("#{MAIL} .tile-page").execute_script("this.focus()")
    %i[arrow_down arrow_down arrow_up arrow_right arrow_left arrow_up arrow_up arrow_up].each do |arrow|
      # To whatever has the keyboard, not to an element: getting to a conversation opens
      # it, which draws the list again under the key
      page.driver.browser.action.send_keys(arrow).perform
      wait_for_turbo
      # In the mailbox, or nowhere for the moment a list is drawn again: from nowhere the
      # next key goes back into the tool (workspace_controller.js#keepKeyboardInTheTool)
      inside = page.evaluate_script("document.activeElement === document.body || Boolean(document.activeElement.closest('turbo-frame.tile-frame'))")
      assert inside, "#{arrow} took the keyboard out of the mailbox"
    end
  end

  private

  def beside_another_tile
    # (a room: still a frame of its own, so the mailbox is the one tile in the page)
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(tools(:my_room)))
    assert_selector "#{TILE} > iframe", count: 1
    find("#{MAIL} .tile-page").execute_script("this.focus()")
  end
end

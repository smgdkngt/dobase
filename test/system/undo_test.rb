# frozen_string_literal: true

require "application_system_test_case"

# What was just archived, trashed or moved comes back with the Undo on the notice that
# says so, or with z (Mails::Undo, shared/flash_undo); mail that was sent off can be
# taken back while it waits to go out (Tools::Mails::SendingsController).
class UndoTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    @message = mails_messages(:inbox_unread)
    sign_in_as(@user)
  end

  test "archived mail comes back to the inbox with Undo" do
    open_message
    find("a[title='Archive (e)']").click
    assert_selector ".mail-detail-header h1", text: "Your weekly report"
    assert_no_selector ".mail-list-item", text: "Welcome to Dobase"

    within(".flash-toast .flash", text: "Email archived.") { click_on "Undo" }

    assert_selector ".flash-toast .flash", text: "Undone."
    assert_selector ".mail-list-item", text: "Welcome to Dobase"
    assert_selector ".mail-detail-header h1", text: "Welcome to Dobase"
    assert_not @message.reload.archived?
  end

  test "z undoes archiving" do
    open_message
    find("a[title='Archive (e)']").click
    assert_selector ".flash-toast .flash", text: "Email archived."
    wait_for_stimulus "hotkey", "[data-flash-undo] [data-controller~='hotkey']"

    page.send_keys("z")

    assert_selector ".flash-toast .flash", text: "Undone."
    assert_selector ".mail-list-item", text: "Welcome to Dobase"
    assert_not @message.reload.archived?
  end

  test "trashed mail comes back with Undo" do
    open_message
    find("[title='Delete (#)']").click
    assert_no_selector ".mail-list-item", text: "Welcome to Dobase"

    within(".flash-toast .flash", text: "Email moved to trash.") { click_on "Undo" }

    assert_selector ".mail-list-item", text: "Welcome to Dobase"
    assert_not @message.reload.trashed?
  end

  test "mail sent off is taken back with Undo, and is in the compose page again as it was" do
    original = mails_messages(:inbox_read)
    visit new_tool_mail_path(@tool, reply_to: original.id, folder: "inbox")
    wait_for_stimulus "compose"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The editor hasn't started" unless evaluate_script("document.querySelector('rhino-editor').hasInitialized")
    end
    find("rhino-editor [contenteditable]").send_keys("Thanks for these")

    click_on "Send"
    assert_selector "[data-controller~='mail-sending']", text: "Sending…"

    within(".mail-sending-note") { click_on "Undo" }

    assert_selector "rhino-editor [contenteditable]", text: "Thanks for these"
    assert_equal "Re: Your weekly report", find("input[name='subject']").value
    assert_selector "li[data-address='#{original.from_address}']"
    reply = @tool.mail_account.messages.find_by!(subject: "Re: Your weekly report", draft: true)
    assert_equal [ "Drafts", false ], reply.values_at(:folder, :sending)

    deliveries = capture_smtp_deliveries { perform_enqueued_jobs(only: SendMailJob) }
    assert_empty deliveries
  end

  test "an archived card comes back with Undo" do
    card = cards(:first_task)
    visit tool_board_path(tools(:project_board))
    find("[data-card-id='#{card.id}']", text: "First task").right_click
    find(".context-menu [role=menuitem]", text: /\AArchive\b/).click
    assert_selector ".flash-toast .flash", text: "Card archived."
    assert card.reload.archived?

    within(".flash-toast .flash", text: "Card archived.") { click_on "Undo" }

    assert_db_change -> { !card.reload.archived? }
    assert_selector "[data-card-id='#{card.id}']", text: "First task"
  end

  test "in a tile of the workspace, z undoes archiving, and the tile shows the mail again" do
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(@tool))
    wait_for_stimulus "workspace"
    mail = ".workspace-tile:not([hidden], [data-leaving]) > turbo-frame.tile-frame"
    assert_selector "#{mail} .mail-list-item", text: "Welcome to Dobase"
    wait_for_stimulus "mail-keyboard"
    within(".workspace-hint") { click_on "Got it" }

    find("#{mail} .mail-list-item", text: "Welcome to Dobase").click
    assert_selector "#{mail} .mail-detail-header h1", text: "Welcome to Dobase"
    find("#{mail} [title='Archive (e)']").click
    assert_db_change -> { @message.reload.archived? }
    assert_selector "#{mail} .mail-detail-header h1", text: "Your weekly report"
    assert_selector ".flash", text: "Email archived."
    wait_for_stimulus "hotkey", "[data-flash-undo] [data-controller~='hotkey']"

    page.send_keys("z")

    assert_db_change -> { !@message.reload.archived? }
    assert_selector "#{mail} .mail-detail-header h1", text: "Welcome to Dobase"
    assert_selector "#{mail} .mail-list-item", text: "Welcome to Dobase"
    assert_current_path workspace_path
  end

  test "in a tile of the workspace, mail sent off is taken back with Undo, into the compose page in that tile" do
    original = mails_messages(:inbox_read)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: new_tool_mail_path(@tool, reply_to: original.id, folder: "inbox"))
    wait_for_stimulus "workspace"
    mail = ".workspace-tile:not([hidden], [data-leaving]) > turbo-frame.tile-frame"
    within(".workspace-hint") { click_on "Got it" }
    wait_for_stimulus "compose"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The editor hasn't started" unless evaluate_script("document.querySelector('rhino-editor').hasInitialized")
    end
    find("#{mail} rhino-editor [contenteditable]").send_keys("Thanks for these")

    within(mail) { click_on "Send" }
    assert_selector "#{mail} [data-controller~='mail-sending']", text: "Sending…"
    within("#{mail} .mail-sending-note") { click_on "Undo" }

    assert_selector "#{mail} rhino-editor [contenteditable]", text: "Thanks for these"
    assert @tool.mail_account.messages.exists?(subject: "Re: Your weekly report", draft: true, sending: false)
    assert_current_path workspace_path
  end

  private

  def open_message
    visit tool_mail_path(@tool, @message, folder: "inbox")
    assert_text @message.body_plain, wait: 5
    wait_for_turbo
    wait_for_stimulus "hotkey", "[data-controller~='hotkey'][title^='Delete']"
  end
end

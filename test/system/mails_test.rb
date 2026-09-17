# frozen_string_literal: true

require "application_system_test_case"

class MailsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    sign_in_as(@user)
  end

  teardown do
    FileUtils.rm_rf(@files) if @files
  end

  test "viewing inbox shows messages" do
    visit tool_mails_path(@tool)

    assert_text "Welcome to Dobase"
    assert_text "Friendly Sender"
    assert_text "Your weekly report"
    assert_text "Reports Bot"
    assert_text "Important info"
    assert_text "The Boss"

    # Trashed and archived messages should not appear in inbox
    assert_no_text "Old spam"
    assert_no_text "Archived conversation"
  end

  test "selecting a message shows detail" do
    visit tool_mails_path(@tool)

    find(".mail-list-item", text: "Welcome to Dobase").click

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5
  end

  test "navigating to starred folder" do
    visit tool_mails_path(@tool)
    wait_for_turbo

    find("button[popovertarget='mail-folder-menu']").click

    within "#mail-folder-menu" do
      click_on "Starred"
    end

    assert_text "Important info"
    assert_text "The Boss"

    # Non-starred messages should not appear
    assert_no_text "Welcome to Dobase"
    assert_no_text "Your weekly report"
  end

  test "starring a message from detail view" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5

    click_with_retry("[title='Star (s)']") { message.reload.starred? }
  end

  test "starring an HTML email keeps its body visible" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_selector("iframe[data-email-frame-target=frame]") { |frame| frame.evaluate_script("this.offsetHeight") > 0 }
    click_with_retry("[title='Star (s)']") { message.reload.starred? }

    assert_selector "[title='Star (s)'] .fill-warning"
    assert_selector("iframe[data-email-frame-target=frame]") { |frame| frame.evaluate_script("this.offsetHeight") > 0 }
  end

  test "archiving a message" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5

    click_with_retry("[title='Archive (e)']") { message.reload.archived? }
  end

  test "trashing a message" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5

    click_with_retry("[title='Delete (#)']") { message.reload.trashed? }
  end

  test "the # shortcut trashes the open message" do
    message = mails_messages(:inbox_unread)
    open_message(message)

    connect_to_imap(FakeImapServer.new) do
      # Typed with Shift, the way a US keyboard does it
      find("body").send_keys("#")
      assert_db_change(-> { message.reload.trashed? })
    end
  end

  test "the # shortcut in the trash deletes the message for good, after asking" do
    message = mails_messages(:trashed_message)
    open_message(message, folder: "trash")

    connect_to_imap(FakeImapServer.new) do
      find("body").send_keys("#")
      within("dialog#turbo-confirm-dialog[open]") do
        assert_text "Permanently delete this email?"
        click_on "Delete forever"
      end
      assert_db_change(-> { !Mails::Message.exists?(message.id) })
    end
  end

  test "Trash in the command palette trashes the open message" do
    message = mails_messages(:inbox_unread)
    open_message(message)
    wait_for_stimulus "keyboard-shortcuts"
    wait_for_stimulus "command-palette"

    connect_to_imap(FakeImapServer.new) do
      find(".sidebar-jump-pill").click
      within("dialog[data-controller='command-palette']") { find("button", text: "Trash").click }
      assert_db_change(-> { message.reload.trashed? })
    end
  end

  test "accepting a calendar invite into a calendar from another calendar tool" do
    team_tool = Tool.create!(name: "Team Calendar", tool_type: tool_types(:calendar), owner: @user)
    launches = Calendars::Account.create!(tool: team_tool, provider: "local").calendars.create!(name: "Launches", remote_id: "local-launches")
    message = mails_messages(:starred_message)
    starts_at = 1.week.from_now.change(hour: 14)
    invite = message.calendar_invites.create!(uid: "tasting@example.com", method: "REQUEST", summary: "Tasting session",
                                              starts_at: starts_at, ends_at: starts_at + 1.hour)

    visit tool_mail_path(@tool, message)
    select "Team Calendar - Launches", from: "Add to calendar"
    click_on "Add to Calendar"

    assert_text "Invite accepted and added to calendar."
    assert_equal launches, invite.reload.added_to_calendar

    click_on "View in Calendar"
    assert_current_path tool_calendar_path(team_tool, week_start: starts_at.to_date)
    assert_text "Tasting session"
  end

  test "sending to a contact picked from the suggestions" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "email-autocomplete"

    deliveries = capture_smtp_deliveries do
      find("input[data-compose-target='to']").set("Friendly")
      find("button[data-email='sender@example.com']").click
      assert_selector "[data-controller='email-autocomplete']", text: "Friendly Sender"
      assert_equal "sender@example.com", find("input[name='to']", visible: :hidden).value

      find("input[name='subject']").set("Hello")
      click_on "Send"
      assert_text "Email sent successfully."
    end

    assert_equal [ "sender@example.com" ], deliveries.sole[:recipients]
  end

  test "attachments go out with the email, however many times files are picked" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor

    deliveries = capture_smtp_deliveries do
      add_recipient "friend@example.com"
      find("input[name='subject']").set("Numbers")
      assert_field "subject", with: "Numbers"
      attach_file "attachments[]", text_file("report.txt", "numbers"), make_visible: true
      attach_file "attachments[]", text_file("notes.txt", "more numbers"), make_visible: true
      assert_text "report.txt"
      assert_text "notes.txt"

      click_on "Send"
      assert_text "Email sent successfully."
    end

    assert_match "report.txt", deliveries.sole[:message]
    assert_match "notes.txt", deliveries.sole[:message]
    sent = @tool.mail_account.messages.sent.find_by!(subject: "Numbers")
    assert_equal [ "notes.txt", "report.txt" ], sent.attachments.pluck(:filename).sort
  end

  test "picked files are listed by name, as text, with their size" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor

    attach_file "attachments[]", text_file("<em>notes.txt", "a" * 1536), make_visible: true

    within("[data-compose-target='attachmentsList']") do
      assert_text "<em>notes.txt"
      assert_text "1.5 KB"
      assert_no_selector "em"
    end
  end

  test "saving a draft, and saving it again" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "compose"

    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")
    click_on "Save Draft"
    assert_text "Draft saved."
    draft = @tool.mail_account.messages.drafts.find_by!(subject: "Plans")
    assert_equal [ "friend@example.com" ], draft.to_addresses_list

    wait_for_stimulus "compose"
    find("input[name='subject']").set("Plans for Friday")
    click_on "Save Draft"
    assert_db_change(-> { draft.reload.subject == "Plans for Friday" })
  end

  test "leaving a reply or forward only asks to discard it once it has been changed" do
    message = mails_messages(:inbox_read)
    visit new_tool_mail_path(@tool, reply_to: message.id)
    wait_for_compose_editor
    wait_for_turbo

    click_on "Project Board"
    assert_current_path tool_board_path(tools(:project_board))

    visit new_tool_mail_path(@tool, forward: message.id)
    wait_for_compose_editor
    find("rhino-editor [contenteditable]").send_keys("FYI")
    assert_selector "rhino-editor [contenteditable]", text: "FYI"
    wait_for_turbo

    dismiss_confirm("You have an unsent message. Discard it?") { click_on "Project Board" }
    assert_current_path new_tool_mail_path(@tool, forward: message.id)
  end

  test "leaving a message that failed to send asks to discard it" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor
    add_recipient "not-an-address"
    click_on "Send"
    assert_text "Invalid email address: not-an-address"
    wait_for_compose_editor
    wait_for_turbo

    dismiss_confirm("You have an unsent message. Discard it?") { click_on "Project Board" }
    assert_selector "input[name='to'][value='not-an-address']", visible: :hidden
  end

  test "bulk select and archive" do
    visit tool_mails_path(@tool)

    unread_message = mails_messages(:inbox_unread)
    read_message = mails_messages(:inbox_read)

    page.execute_script(<<~JS)
      const form = document.getElementById('bulk-form');
      const checkboxes = form.querySelectorAll('.mail-list-checkbox');
      checkboxes[0].checked = true;
      checkboxes[1].checked = true;

      const actionInput = document.createElement('input');
      actionInput.type = 'hidden';
      actionInput.name = 'action_type';
      actionInput.value = 'archive';
      form.appendChild(actionInput);
      form.submit();
    JS

    assert_text "2 email(s) archived."
    assert_no_text "Welcome to Dobase"
    assert_no_text "Your weekly report"
    assert unread_message.reload.archived?
    assert read_message.reload.archived?
  end

  test "the mail page doesn't sync when auto-refresh is disabled" do
    account = @tool.mail_account
    account.update!(auto_refresh_interval: 0)

    visit tool_mails_path(@tool)
    wait_for_stimulus "mail-refresh"
    # Disabled used to ask for a sync right away, and then nonstop
    sleep 1

    assert account.reload.synced?, "the mail page asked for a sync"
  end

  test "the mail page follows a new auto-refresh interval without reconnecting" do
    account = @tool.mail_account
    account.update!(auto_refresh_interval: 300)

    visit tool_mails_path(@tool)
    wait_for_stimulus "mail-refresh"
    # What the morph refresh after saving the settings does
    find("[data-controller~='mail-refresh']").execute_script("this.dataset.mailRefreshIntervalValue = '1'")

    assert_db_change(-> { account.reload.syncing? })
  end

  test "mail settings that can't be saved show what to fix" do
    open_mail_settings
    within "dialog#edit-tool-modal[open]" do
      click_on "Email"
      fill_in "IMAP Server", with: "   "
      click_on "Save Changes"
    end

    assert_text "IMAP server can't be blank"
    fill_in "IMAP Server", with: "imap.fixed.example.com"
    click_on "Save Changes"

    assert_text "Mail account updated successfully."
    assert_equal "imap.fixed.example.com", @tool.mail_account.reload.imap_host
  end

  private

  # The editor takes the prefilled body, and typing, once it has started. Headless Chrome
  # can drop input that arrives before the page has shown a frame, so wait for two.
  def wait_for_compose_editor
    wait_for_stimulus "compose"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The editor hasn't started" unless evaluate_script("document.querySelector('rhino-editor').hasInitialized")
    end
    page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
  end

  def add_recipient(address)
    find("input[data-compose-target='to']").set(address).send_keys(:enter)
  end

  def text_file(name, content)
    @files ||= Dir.mktmpdir
    File.join(@files, name).tap { |path| File.write(path, content) }
  end

  def open_message(message, folder: nil)
    visit tool_mail_path(@tool, message, folder: folder)
    assert_text message.body_plain, wait: 5
    wait_for_turbo
    wait_for_stimulus "hotkey", "[data-controller~='hotkey'][title^='Delete']"
  end

  def open_mail_settings
    visit tool_mails_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sidebar"
    # The settings gear only shows on hover
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{@tool.id}']", visible: :all).execute_script("this.click()")
  end

  # Click an element and retry if the expected condition isn't met.
  # Turbo method links sometimes fail to fire in headless Chrome.
  def click_with_retry(selector, retries: 3, &condition)
    wait_for_turbo
    (retries + 1).times do |attempt|
      find(selector).click
      assert_db_change(condition, timeout: 5)
      return
    rescue RuntimeError
      raise if attempt == retries
      sleep 0.5
    end
  end
end

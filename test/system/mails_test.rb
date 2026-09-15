# frozen_string_literal: true

require "application_system_test_case"

class MailsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    sign_in_as(@user)
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

  private

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

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end

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

    assert_selector "h1.text-base.font-semibold", text: "Welcome to Dobase"
    assert_text "Welcome to Dobase! We hope you enjoy the platform."
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
    visit tool_mails_path(@tool, selected: message.id)

    assert_selector "h1.text-base.font-semibold", text: "Welcome to Dobase"

    find("[title='Star (s)']").click

    # Wait for Turbo to complete the redirect (method changes to DELETE after starring)
    assert_selector "[title='Star (s)'][data-turbo-method='delete']", wait: 5

    assert message.reload.starred?

    # Navigate to starred folder and verify the message appears
    find("button[popovertarget='mail-folder-menu']").click

    within "#mail-folder-menu" do
      click_on "Starred"
    end

    assert_text "Welcome to Dobase"
  end

  test "archiving a message" do
    message = mails_messages(:inbox_unread)
    visit tool_mails_path(@tool, selected: message.id)

    assert_selector "h1.text-base.font-semibold", text: "Welcome to Dobase"

    find("[title='Archive (e)']").click

    assert_text "Email archived."
    # Detail panel still shows the message (redirect_back preserves selected param),
    # but the message should be gone from the list
    within ".mail-list-panel" do
      assert_no_text "Welcome to Dobase"
    end
    assert message.reload.archived?
  end

  test "trashing a message" do
    message = mails_messages(:inbox_unread)
    visit tool_mails_path(@tool, selected: message.id)

    assert_selector "h1.text-base.font-semibold", text: "Welcome to Dobase"

    find("[title='Delete (#)']").click

    assert_text "Email moved to trash."
    within ".mail-list-panel" do
      assert_no_text "Welcome to Dobase"
    end
    assert message.reload.trashed?
  end

  test "bulk select and archive" do
    visit tool_mails_path(@tool)

    unread_message = mails_messages(:inbox_unread)
    read_message = mails_messages(:inbox_read)

    # Check specific checkboxes and submit form via JS for reliability
    # (Capybara checkbox clicks inside mail-list-items can trigger navigation)
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

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end

# frozen_string_literal: true

require "application_system_test_case"

# Connecting a mail account: a known service fills in its servers, and a login the
# server turns down is said on the form. A sync that stopped later says so above the list.
class MailConnectTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "picking a service fills in its servers and says where to make an app password" do
    tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: @user)
    visit new_tool_mails_account_path(tool)

    assert_selector "details.mail-connect-servers[open]"
    click_on "iCloud"

    assert_selector "button[aria-pressed='true']", text: "iCloud"
    assert_no_selector "details.mail-connect-servers[open]"
    assert_selector ".mail-provider-hint", text: "app-specific password"
    assert_selector ".mail-provider-hint a[href='https://support.apple.com/en-us/102654']", text: "How to make an app password"

    find("summary", text: "Server settings").click
    assert_field "IMAP server", with: "imap.mail.me.com"
    assert_field "mails_account[imap_port]", with: "993"
    assert_field "SMTP server", with: "smtp.mail.me.com"
    assert_field "mails_account[smtp_port]", with: "587"
    assert_checked_field "Use STARTTLS"

    click_on "Other"
    assert_field "IMAP server", with: ""
    assert_selector "details.mail-connect-servers[open]"
    assert_no_selector ".mail-provider-hint"
  end

  test "an address of a known service picks it, and is the username until another is typed" do
    tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: @user)
    visit new_tool_mails_account_path(tool)

    fill_in "Email address", with: "ann@gmail.com"

    assert_selector "button[aria-pressed='true']", text: "Gmail"
    assert_field "Username", with: "ann@gmail.com"
    assert_field "IMAP server", with: "imap.gmail.com", visible: :all

    fill_in "Username", with: "ann"
    fill_in "Email address", with: "ann.lee@gmail.com"
    assert_field "Username", with: "ann"
  end

  test "a login the server turns down is said on the form, which keeps the service" do
    tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: @user)
    visit new_tool_mails_account_path(tool)
    click_on "Fastmail"
    fill_in "Email address", with: "ann@fastmail.com"
    fill_in "Password", with: "wrong"

    with_mail_servers(imap: FakeImapServer.new(refuses_login: "Invalid credentials")) do
      click_on "Connect"
      assert_selector ".flash-error", text: "Incoming mail (imap.fastmail.com): the mail server didn't accept the username or password."
    end

    assert_selector "button[aria-pressed='true']", text: "Fastmail"
    assert_nil tool.reload.mail_account
  end

  test "a mailbox whose sync stopped says why above the list, on a phone too" do
    account = mails_accounts(:primary)
    account.mark_sync_error!(Mails::Account::AUTHENTICATION_FAILED)
    page.current_window.resize_to(390, 844)

    visit tool_mails_path(tools(:my_mail))

    assert_selector ".mail-sync-problem", text: "the mail server didn't accept the username or password."
    within(".mail-sync-problem") do
      assert_selector "a", text: "Try again", visible: true
      click_on "Settings"
    end
    assert_selector "[data-tab='email'] input[name='mails_account[password]']", visible: true
  end
end

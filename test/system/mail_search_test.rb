# frozen_string_literal: true

require "application_system_test_case"

# Searching a mailbox from its page: every folder at once, each result saying where it
# is, narrowed to one folder from the menu over the results
class MailSearchTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    account = mails_accounts(:primary)
    account.update!(synced_folders: %w[INBOX Sent Receipts].to_json)
    account.messages.create!(message_id: "<harbour-1@example.com>", folder: "Receipts", subject: "Harbour fees for March",
      from_address: "port@example.com", sent_at: 2.days.ago, read: true)
    account.messages.create!(message_id: "<harbour-2@example.com>", folder: "Sent", subject: "Moorings",
      body_plain: "See you at the harbour", from_address: account.email_address, sent_at: 1.day.ago, read: true)
    sign_in_as(@user)
  end

  test "a search from the inbox finds mail in other folders, and the menu narrows it to one" do
    visit tool_mails_path(@tool)
    find("input[name=q]").fill_in(with: "harb\n")

    assert_selector ".mail-list-item", count: 2
    assert_selector ".mail-list-item", text: "Harbour fees for March" do
      assert_selector ".mail-list-folder", text: "Receipts"
    end
    assert_selector ".mail-list-item", text: "Moorings" do
      assert_selector ".mail-list-folder", text: "Sent"
    end

    find(".mail-search-pick").click
    within("#mail-search-in-#{@tool.id}") { click_on "Receipts" }

    assert_selector ".mail-list-item", count: 1
    assert_selector ".mail-search-pick", text: "Receipts"
    assert_field "q", with: "harb"

    click_on "Clear"
    assert_no_selector ".mail-search-header"
    assert_no_selector ".mail-list-item", text: "Harbour fees"
  end
end

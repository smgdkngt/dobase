# frozen_string_literal: true

require "application_system_test_case"

# A file opened from where it hangs: the viewer comes over the page, shows what was read
# out of the file, and goes away again.
class FileViewerTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    sign_in_as(@user)
  end

  def attach(message, name, content)
    attachment = message.attachments.create!(filename: name, content_type: "application/octet-stream", file_size: content.bytesize)
    attachment.file.attach(io: StringIO.new(content), filename: name, content_type: "application/octet-stream", identify: false)
    attachment
  end

  test "a spreadsheet attached to a mail opens over the page, closes, and opens again" do
    message = mails_messages(:inbox_unread)
    attach(message, "budget.xlsx", file_fixture("sample.xlsx").binread)

    visit tool_mail_path(@tool, message)
    click_link "budget.xlsx"

    within "dialog#file-viewer[open]" do
      assert_selector "h2", text: "budget.xlsx"
      assert_selector "td", text: "42.5"
      assert_link "Download"
      click_button "Close"
    end
    assert_no_selector "dialog#file-viewer[open]"

    click_link "budget.xlsx"

    assert_selector "dialog#file-viewer[open] td", text: "42.5"
  end

  test "a draft's attachment can be looked at while the mail is being written" do
    draft = mails_messages(:draft_message)
    attach(draft, "figures.csv", "Month;Total\nOctober;42\n")

    visit new_tool_mail_path(@tool, draft_id: draft.id)
    click_link "figures.csv"

    assert_selector "dialog#file-viewer[open] td", text: "October"

    send_keys :escape

    assert_no_selector "dialog#file-viewer[open]"
    # Still writing the same mail
    assert_selector "form [data-compose-target='attachmentsList']", visible: :all
  end
end

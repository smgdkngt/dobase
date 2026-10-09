# frozen_string_literal: true

require "test_helper"

# Wherever a file hangs on something, its name opens it in the viewer over the page
# (shared/file_viewer) and an arrow beside it downloads it: a mail, a mail that is being
# written, a card, a todo, a chat message. And every page has the viewer to open it in.
class FilePreviewLinksTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  def attached(record, name, content_type: "text/plain")
    record.file.attach(io: StringIO.new("Hello"), filename: name, content_type: content_type, identify: false)
    record.file
  end

  # A link to the file in the viewer, and one that downloads it
  def assert_opens_and_downloads(tool, file)
    assert_select "a[href='#{tool_file_preview_path(tool, file.attachment)}'][data-turbo-frame='file_viewer']"
    assert_select "a.file-download-link[download][href*='disposition=attachment']"
  end

  test "every page has the viewer" do
    get tool_files_path(tools(:my_files))

    assert_select "dialog#file-viewer[data-controller~='file-viewer'] turbo-frame#file_viewer"
  end

  test "an attachment of a mail" do
    message = mails_messages(:inbox_unread)
    file = attached(message.attachments.create!(filename: "budget.xlsx", content_type: "application/octet-stream", file_size: 5), "budget.xlsx")

    get tool_mail_path(tools(:my_mail), message)

    assert_response :success
    assert_opens_and_downloads tools(:my_mail), file
  end

  test "an attachment of a mail that is being written" do
    draft = mails_messages(:draft_message)
    file = attached(draft.attachments.create!(filename: "budget.xlsx", content_type: "application/octet-stream", file_size: 5), "budget.xlsx")

    get new_tool_mail_path(tools(:my_mail), draft_id: draft.id)

    assert_response :success
    assert_select "form" do
      assert_opens_and_downloads tools(:my_mail), file
      # Its own list, apart from the one the script draws the files picked just now in
      assert_select "[data-compose-target='attachmentsList'] a", 0
    end
  end

  test "an attachment of a card" do
    card = cards(:first_task)
    file = attached(card.attachments.create!(filename: "brief.pdf", content_type: "application/pdf", file_size: 5), "brief.pdf")

    get tool_board_card_path(tools(:project_board), card)

    assert_response :success
    assert_opens_and_downloads tools(:project_board), file
  end

  test "an attachment of a todo" do
    item = todo_items(:pending_one)
    file = attached(item.attachments.create!(filename: "notes.txt", content_type: "text/plain", file_size: 5), "notes.txt")

    get tool_todo_item_path(item.list.tool, item)

    assert_response :success
    assert_opens_and_downloads item.list.tool, file
  end

  test "a picture and a file in a chat" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") do |tool_type|
      tool_type.name = "Chat"
      tool_type.icon = "messages-square"
    end
    tool = Tool.create!(name: "Team chat", owner: @user, tool_type: chat_type)
    message = tool.chat.messages.create!(user: @user, body: "<p>Look</p>", files: [
      { io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png" },
      { io: StringIO.new("a,b\n"), filename: "list.csv", content_type: "text/csv" }
    ])

    get tool_chat_path(tool)

    assert_response :success
    message.files.each do |file|
      assert_select "a[href='#{tool_file_preview_path(tool, file)}'][data-turbo-frame='file_viewer']"
    end
    assert_select "a.file-download-link[download][href*='disposition=attachment']", 1
  end

  test "the API says where a file is read" do
    message = mails_messages(:inbox_unread)
    file = attached(message.attachments.create!(filename: "budget.xlsx", content_type: "application/octet-stream", file_size: 5), "budget.xlsx")

    get tool_mail_path(tools(:my_mail), message), headers: api_headers(@user, permission: "read")

    assert_response :success
    assert_includes response.body, tool_file_preview_url(tools(:my_mail), file.attachment, format: :json)
  end
end

# frozen_string_literal: true

require "test_helper"

# The download of a file in a mail, a card, a todo or a chat goes through the tool's own
# check, like its preview: a copied link is no use to anyone who isn't in the tool.
class Tools::FileDownloadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  def mail_attachment(message, name, content)
    attachment = message.attachments.create!(filename: name, content_type: "text/plain", file_size: content.bytesize)
    attachment.file.attach(io: StringIO.new(content), filename: name, content_type: "text/plain", identify: false)
    attachment.file.attachment
  end

  def follow_to_the_file
    follow_redirect! while response.redirect?
    response.body
  end

  test "someone in the tool gets the file, from a storage link that lasts minutes" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello")
    sign_in_as @user

    get tool_file_download_path(tools(:my_mail), attachment)

    assert_response :redirect
    assert_includes response.location, "disposition=attachment"
    assert_equal "Hello", follow_to_the_file
  end

  test "without signing in there is no file" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello")

    get tool_file_download_path(tools(:my_mail), attachment)

    assert_redirected_to new_session_path
    assert_not_includes response.body, "Hello"
  end

  test "a file in a tool you don't have isn't given" do
    attachment = mail_attachment(mails_messages(:other_inbox), "secret.txt", "Secret")
    sign_in_as @user

    get tool_file_download_path(tools(:other_mail), attachment)

    assert_redirected_to root_path
    assert_not_includes response.body, "Secret"
  end

  test "another tool's id doesn't get you a file you may not see" do
    attachment = mail_attachment(mails_messages(:other_inbox), "secret.txt", "Secret")
    sign_in_as @user

    get tool_file_download_path(tools(:my_mail), attachment)

    assert_redirected_to root_path
  end

  test "what isn't a tool's file is never given: someone's avatar" do
    users(:two).avatar.attach(io: file_fixture("sample.png").open, filename: "them.png", content_type: "image/png")
    sign_in_as @user

    get tool_file_download_path(tools(:my_mail), users(:two).avatar.attachment)

    assert_redirected_to root_path
  end

  test "an access token gets the file too, and the API hands out this address" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello")
    headers = api_headers(@user, permission: "read")

    get tool_mail_path(tools(:my_mail), mails_messages(:inbox_unread), format: :json), headers: headers
    assert_response :success
    attachments = response.parsed_body["messages"].flat_map { |message| message["attachments"] }
    download = attachments.find { |file| file["filename"] == "notes.txt" }["download_url"]
    assert_equal tool_file_download_url(tools(:my_mail), attachment), download

    get download, headers: headers
    assert_response :redirect
    assert_equal "Hello", follow_to_the_file
  end
end

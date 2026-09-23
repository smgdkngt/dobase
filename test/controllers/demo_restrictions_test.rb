# frozen_string_literal: true

require "test_helper"

# What reaches outside the app is switched off in the demo, and only there
class DemoRestrictionsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "connecting a mail account" do
    tool = Tool.create!(name: "Inbox", tool_type: tool_types(:mail), owner: users(:one))
    params = { mails_account: { email_address: "me@example.com", imap_host: "imap.example.com", smtp_host: "smtp.example.com", smtp_auth: "plain", username: "me", password: "secret" } }

    in_demo_mode do
      assert_no_enqueued_jobs do
        post tool_mails_account_path(tool), params: params, headers: { "Referer" => tool_path(tool) }
      end
    end
    assert_refused_in_demo
    assert_nil tool.reload.mail_account

    post tool_mails_account_path(tool), params: params
    assert tool.reload.mail_account
  end

  test "sending mail" do
    in_demo_mode do
      post tool_mails_path(tools(:my_mail)), params: { to: "friend@example.com", subject: "Hi", body: "<p>Hi</p>" }, as: :json
    end

    assert_response :forbidden
    assert_equal({ "error" => "Not available in the demo" }, response.parsed_body)
  end

  test "syncing mail" do
    in_demo_mode do
      assert_no_enqueued_jobs do
        post tool_sync_path(tools(:my_mail)), as: :json
      end
    end

    assert_response :forbidden
    assert_not mails_accounts(:primary).reload.syncing?
  end

  test "uploading" do
    file = -> { Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "notes.txt") }

    in_demo_mode do
      assert_no_difference "Files::Item.count" do
        post tool_files_uploads_path(tools(:my_files)), params: { file: file.call }, headers: { "Accept" => "application/json" }
      end
      assert_response :forbidden

      post rails_direct_uploads_path, params: { blob: { filename: "a.png", byte_size: 2, checksum: "x", content_type: "image/png" } }, as: :json
      assert_response :forbidden
    end

    assert_difference "Files::Item.count" do
      post tool_files_uploads_path(tools(:my_files)), params: { file: file.call }, headers: { "Accept" => "application/json" }
    end
  end

  test "a chat message may be sent, but without files" do
    chat_tool = Tool.create!(name: "Team Chat", owner: users(:one), tool_type: ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle"))
    file = Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "notes.txt")

    in_demo_mode do
      assert_no_difference "Chats::Message.count" do
        post tool_chat_messages_path(chat_tool), params: { message: { body: "<p>Look</p>", files: [ file ] } }, headers: { "Accept" => "application/json" }
      end
      assert_response :forbidden

      assert_difference "Chats::Message.count" do
        post tool_chat_messages_path(chat_tool), params: { message: { body: "<p>Hi</p>" } }, as: :json
      end
    end
  end

  test "sharing a file publicly" do
    file = file_items(:report)

    in_demo_mode do
      post tool_files_item_share_path(tools(:my_files), file), headers: { "Referer" => tool_files_path(tools(:my_files)) }
    end
    assert_refused_in_demo
    assert_nil file.reload.share

    post tool_files_item_share_path(tools(:my_files), file)
    assert file.reload.share
  end

  test "the share dialog says public links are off" do
    in_demo_mode { get tool_files_item_share_path(tools(:my_files), file_items(:report)) }

    assert_includes response.body, "Public links are switched off in the demo."
    assert_not_includes response.body, "Create Link"
  end

  test "inviting someone" do
    tool = tools(:shared_board)

    in_demo_mode do
      assert_no_difference -> { tool.invitations.count } do
        post tool_collaborators_path(tool), params: { email: "newcomer@example.com" }
      end
    end
    assert_equal "That's switched off in the demo.", flash[:alert]

    post tool_collaborators_path(tool), params: { email: "newcomer@example.com" }
    assert tool.invitations.exists?(email: "newcomer@example.com")
  end

  test "a form in the tool settings stays open and says why nothing happened" do
    in_demo_mode do
      post tool_collaborators_path(tools(:shared_board)), params: { email: "newcomer@example.com" }, as: :turbo_stream
    end

    assert_response :forbidden
    assert_select "turbo-stream[action=replace][target=flash] template", text: /That's switched off in the demo\./
  end

  test "connecting a CalDAV calendar, but not making a local one" do
    caldav = Tool.create!(name: "Work", tool_type: tool_types(:calendar), owner: users(:one))
    local = Tool.create!(name: "Home", tool_type: tool_types(:calendar), owner: users(:one))

    in_demo_mode do
      post tool_calendar_account_path(caldav), params: { calendars_account: { provider: "custom", caldav_url: "https://caldav.example.com/", username: "me", password: "secret" } }
      assert_equal "That's switched off in the demo.", flash[:alert]
      assert_nil caldav.reload.calendar_account

      post tool_calendar_account_path(local), params: { calendars_account: { provider: "local" } }
      assert_redirected_to tool_calendar_path(local)
      assert local.reload.calendar_account.local?
    end
  end

  test "signing up" do
    sign_out

    in_demo_mode { get signup_path }
    assert_redirected_to login_path
  end

  test "changing the address a visitor is known by" do
    in_demo_mode do
      patch profile_path, params: { user: { first_name: "Ada", email_address: "ada@example.com" } }
    end

    assert_equal "Ada", users(:one).reload.first_name
    assert_equal "one@example.com", users(:one).email_address
  end

  private

  def assert_refused_in_demo
    assert_response :redirect
    assert_equal "That's switched off in the demo.", flash[:alert]
  end
end

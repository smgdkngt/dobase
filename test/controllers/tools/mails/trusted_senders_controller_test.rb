# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class TrustedSendersControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
        @account = @tool.mail_account
        @message = mails_messages(:inbox_unread)
        @message.update!(body_html: %(<p>Hello</p><img src="https://tracker.example.com/logo.png">))
      end

      test "images are hidden until the sender is trusted" do
        get tool_mail_path(@tool, @message)

        assert_select "iframe[srcdoc*='data-blocked-src']"
        assert_select "button[aria-label='Always show images from sender@example.com']", text: "Always for this sender"
      end

      test "create trusts the sender, and their mail shows its images" do
        post tool_mail_trusted_sender_path(@tool, @message)

        assert @account.shows_images_from?("Sender@Example.com")
        get tool_mail_path(@tool, @message)
        assert_select "iframe[srcdoc*='https://tracker.example.com/logo.png']"
        # Said in passing, not in a box above every mail of theirs
        assert_select ".email-images-note-quiet", text: /Images shown for this sender/
        assert_select "button[aria-label='Stop showing images from sender@example.com']", text: "Stop"
      end

      test "create twice keeps one trusted sender" do
        2.times { post tool_mail_trusted_sender_path(@tool, @message) }

        assert_equal 1, @account.trusted_senders.count
      end

      test "destroy stops trusting the sender" do
        @account.trusted_senders.create!(email_address: "SENDER@example.com")

        delete tool_mail_trusted_sender_path(@tool, @message)

        assert_not @account.shows_images_from?("sender@example.com")
      end

      # A tile that is part of the workspace's page sends its forms from the workspace's
      # address. Sent back there, a tile is sent on to the start page, which shows a
      # tile nothing but "Create your first tool".
      test "from a tile in the workspace's page it leads back to where the tile is" do
        open_mail = tool_mail_path(@tool, @message, folder: "inbox")

        post tool_mail_trusted_sender_path(@tool, @message),
             headers: { "Referer" => workspace_url, "X-Tile" => "1", "X-Tile-Address" => open_mail }

        assert_redirected_to open_mail
        follow_redirect! headers: { "X-Tile" => "1" }
        assert_response :success
        assert_select ".email-images-note-quiet", text: /Images shown for this sender/
        assert_select "button", text: /Create your first tool/, count: 0
      end

      test "from a tile that doesn't say where it is, it leads to the mail" do
        @account.trusted_senders.create!(email_address: "sender@example.com")

        delete tool_mail_trusted_sender_path(@tool, @message), headers: { "Referer" => workspace_url, "X-Tile" => "1" }

        assert_redirected_to tool_mail_path(@tool, @message)
      end

      test "a tile is only sent back to a page of the tool it is about" do
        [ "https://elsewhere.example/tools/#{@tool.id}/mails", "//elsewhere.example", "/profile", tool_path(tools(:project_board)) ].each do |address|
          post tool_mail_trusted_sender_path(@tool, @message),
               headers: { "Referer" => workspace_url, "X-Tile" => "1", "X-Tile-Address" => address }

          assert_redirected_to tool_mail_path(@tool, @message), "sent to #{address}"
        end
      end

      test "from a page of its own it leads back to that page" do
        post tool_mail_trusted_sender_path(@tool, @message), headers: { "Referer" => tool_mails_url(@tool, folder: "archive") }

        assert_redirected_to tool_mails_url(@tool, folder: "archive")
      end

      test "your own mail shows its images" do
        assert @account.shows_images_from?("TestUser@example.com")
      end

      test "a message from another account's mail trusts nobody" do
        post tool_mail_trusted_sender_path(@tool, mails_messages(:other_inbox))

        assert_empty @account.trusted_senders
      end
    end
  end
end

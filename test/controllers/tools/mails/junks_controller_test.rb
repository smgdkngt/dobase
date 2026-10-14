# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    # Junk is the mail server's junk folder, shown beside the trash for an account that has
    # one: mail the server took for spam, which can be mail someone was waiting for
    class JunksControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
        @account = mails_accounts(:primary)
        @account.update!(synced_folders: %w[INBOX Sent Archive Receipts Junk Trash].to_json)
        @junk = @account.messages.create!(message_id: "<invite@hans.example>", folder: "Junk", uid: 31, subject: "Uitnodiging",
          from_address: "hans@hans.example", from_name: "Hans", sent_at: 1.hour.ago, read: false,
          body_html: %(<p>Kom je ook?</p><img src="https://tracker.example/open.gif"><a href="https://hans.example/rsvp">Ja</a>))
      end

      test "an account whose server has a junk folder shows Junk beside the trash, with its unread mail counted there and not in the inbox" do
        get tool_mails_path(@tool)

        assert_select ".mail-folder-rail a", text: /Junk/ do |links|
          assert_select links, ".badge", text: "1"
        end
        assert_equal %w[Archive Junk Trash], css_select(".mail-folder-rail a").map { |link| link.text.strip[/\A\w+/] }.first(7).last(3)
        assert_not_includes response.body, "Uitnodiging"
        assert_equal @account.messages.inbox.unread.count, users(:one).unread_mail_count

        get tool_mails_path(@tool, folder: "junk")

        assert_includes response.body, "Uitnodiging"
        assert_includes response.body, "Mail your server took for junk"
      end

      test "an account without a junk folder has no Junk" do
        @account.update!(synced_folders: %w[INBOX Sent Trash].to_json)

        get tool_mails_path(@tool)

        assert_select ".mail-folder-rail a", text: /Junk/, count: 0
        assert_select "button", text: "Junk", count: 0
      end

      test "mail in junk keeps its images hidden, also from a trusted sender, and offers no trust" do
        @account.trusted_senders.create!(email_address: "hans@hans.example")

        get tool_mail_path(@tool, @junk, folder: "junk")

        assert_includes response.body, "Images are hidden"
        assert_select "button", text: "Always for this sender", count: 0
        assert_select "iframe[srcdoc*=?]", "tracker.example", count: 0

        # The same mail in the inbox is the sender's, whose images show
        @junk.update!(folder: "INBOX")
        get tool_mail_path(@tool, @junk)
        assert_select "iframe[srcdoc*=?]", "tracker.example"
      end

      test "Not junk moves the conversation to the inbox, here at once and on the server" do
        reply = @account.messages.create!(message_id: "<invite-2@hans.example>", folder: "Junk", uid: 32, subject: "Re: Uitnodiging",
          from_address: "hans@hans.example", sent_at: 30.minutes.ago, in_reply_to: @junk.message_id)
        server = FakeImapServer.new(folders: [ "INBOX", [ "INBOX.spam", :Junk ] ])

        get tool_mail_path(@tool, reply, folder: "junk")
        assert_select "a[href=?][data-turbo-method=delete]", tool_mail_junk_path(@tool, reply), text: /Not junk/

        connect_to_imap(server) { perform_enqueued_jobs(only: ImapSyncJob) { delete tool_mail_junk_path(@tool, reply) } }

        assert_redirected_to tool_mails_path(@tool, folder: "junk")
        assert_equal [ [ "INBOX", nil ], [ "INBOX", nil ] ], [ @junk.reload, reply.reload ].map { |message| [ message.folder, message.uid ] }
        assert_equal [ [ 31, "INBOX" ], [ 32, "INBOX" ] ], server.copied.sort
        assert_equal [ "INBOX.spam" ], server.selected.uniq
      end

      test "mail in the inbox moves to junk from the move menu" do
        message = mails_messages(:inbox_read)
        message.update!(uid: 21)
        server = FakeImapServer.new(folders: [ "INBOX", [ "Junk", :Junk ] ])

        get tool_mail_path(@tool, message)
        assert_select "#move-to-menu form[action=?]", tool_mail_junk_path(@tool, message)

        connect_to_imap(server) { perform_enqueued_jobs(only: ImapSyncJob) { post tool_mail_junk_path(@tool, message, folder: "inbox") } }

        assert message.reload.junk?
        assert_equal [ [ 21, "Junk" ] ], server.copied
      end

      test "nothing moves to junk on a server without a junk folder" do
        @account.update!(synced_folders: %w[INBOX Sent].to_json)
        message = mails_messages(:inbox_read)

        post tool_mail_junk_path(@tool, message)

        assert_equal "INBOX", message.reload.folder
        assert_equal "This account's mail server has no junk folder.", flash[:alert]
      end

      test "several at once, from the list" do
        message = mails_messages(:inbox_read)

        post tool_bulk_path(@tool), params: { message_ids: [ message.id ], action_type: "junk", folder: "inbox" }
        assert message.reload.junk?

        post tool_bulk_path(@tool), params: { message_ids: [ message.id, @junk.id ], action_type: "not_junk", folder: "junk" }
        assert_equal %w[INBOX INBOX], [ message.reload.folder, @junk.reload.folder ]
      end

      test "through the API, with a token" do
        headers = api_headers(users(:one))

        get tool_mails_path(@tool, folder: "junk"), headers: headers, as: :json
        assert_equal [ "inbox", "drafts", "starred", "sent", "archive", "junk", "trash" ], response.parsed_body["folders"]
        assert_equal 1, response.parsed_body.dig("counts", "junk_unread")
        assert_equal [ "Uitnodiging" ], response.parsed_body["conversations"].pluck("subject")

        delete tool_mail_junk_path(@tool, @junk), headers: headers, as: :json
        assert_response :success
        assert_equal "INBOX", response.parsed_body["folder"]

        post tool_mail_junk_path(@tool, @junk), headers: headers, as: :json
        assert_equal "Junk", response.parsed_body["folder"]

        @account.update!(synced_folders: %w[INBOX Sent].to_json)
        post tool_mail_junk_path(@tool, mails_messages(:inbox_read)), headers: headers, as: :json
        assert_response :unprocessable_entity
        get tool_mails_path(@tool), headers: headers, as: :json
        assert_not_includes response.parsed_body["folders"], "junk"
        assert_nil response.parsed_body.dig("counts", "junk_unread")
      end
    end
  end
end

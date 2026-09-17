# frozen_string_literal: true

require "test_helper"

module Tools
  class MailApiTest < ActionDispatch::IntegrationTest
    # Stand-ins for the IMAP and SMTP services, so no test talks to a mail server.
    # Background jobs are only enqueued in tests, never performed.
    class FakeImap
      attr_reader :calls

      def initialize
        @calls = []
      end

      def delete_message(uid, folder:)
        @calls << [ :delete_message, uid, folder ]
      end

      def delete_draft(uid)
        @calls << [ :delete_draft, uid ]
      end
    end

    class FakeSmtp
      attr_reader :sent
      attr_accessor :failure

      def initialize
        @sent = []
      end

      def send_email(**email)
        raise SmtpSendService::SendError, failure if failure

        @sent << email
        true
      end
    end

    setup do
      @user = users(:one)
      @headers = api_headers(@user)
      @tool = tools(:my_mail)
      @account = mails_accounts(:primary)

      @imap = FakeImap.new
      @smtp = FakeSmtp.new
      fake_service ImapSyncService, @imap
      fake_service SmtpSendService, @smtp
    end

    teardown do
      @faked_services&.each { |service| service.singleton_class.remove_method(:new) }
    end

    test "index lists inbox conversations with counts and folders" do
      get tool_mails_path(@tool), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal "testuser@example.com", body.dig("account", "email_address")
      assert_equal "inbox", body["folder"]
      assert_equal [ 1, 1, 3 ], body.values_at("page", "total_pages", "total_count")
      assert_equal({ "inbox_unread" => 1, "drafts" => 1, "trash" => 1 }, body["counts"])
      assert_equal %w[inbox drafts starred sent archive trash], body["folders"]
      assert_equal %w[Archive Receipts], body["custom_folders"]
      assert_equal [ "Welcome to Dobase", "Your weekly report", "Important info" ], body["conversations"].map { |conversation| conversation["subject"] }

      welcome = body["conversations"].first
      message = mails_messages(:inbox_unread)
      assert_equal message.id, welcome["id"]
      assert_equal [ "Friendly Sender", "sender@example.com" ], welcome.values_at("from", "from_address")
      assert_equal [ false, false, false ], welcome.values_at("read", "starred", "draft")
      assert_equal [ 1, 1 ], welcome.values_at("messages_count", "unread_count")
      assert_equal tool_mail_url(@tool, message, folder: "inbox"), welcome["url"]
    end

    test "index sums up a conversation of several messages" do
      original = mails_messages(:inbox_unread)
      @tool.mail_account.messages.create!(message_id: "reply-1@example.com", thread_id: original.thread_id, folder: "INBOX",
        subject: "Re: Welcome to Dobase", from_name: "Colleague", from_address: "colleague@example.com",
        sent_at: 1.minute.from_now, read: true, starred: true, has_attachments: true)

      get tool_mails_path(@tool), headers: @headers

      welcome = response.parsed_body["conversations"].first
      assert_equal original.thread_id, welcome["thread_id"]
      assert_equal "Colleague", welcome["from"]
      assert_equal [ false, true, true ], welcome.values_at("read", "starred", "has_attachments")
      assert_equal [ 2, 1 ], welcome.values_at("messages_count", "unread_count")
      assert_equal [ "Colleague", "Friendly Sender" ], welcome["participants"]
      assert_equal 3, response.parsed_body["total_count"]
    end

    test "index pages through conversations, newest first" do
      31.times do |index|
        @tool.mail_account.messages.create!(message_id: "bulk-#{index}@example.com", folder: "INBOX", subject: "Bulk #{index}",
          from_address: "bulk@example.com", sent_at: (index + 1).days.ago)
      end

      get tool_mails_path(@tool, page: 2), headers: @headers

      body = response.parsed_body
      assert_equal [ 2, 2, 34 ], body.values_at("page", "total_pages", "total_count")
      assert_equal 4, body["conversations"].size
      assert_equal "Bulk 30", body["conversations"].last["subject"]
    end

    test "index filters by folder and search" do
      get tool_mails_path(@tool, folder: "sent"), headers: @headers
      assert_equal [ "Weekly report" ], response.parsed_body["conversations"].map { |conversation| conversation["subject"] }

      get tool_mails_path(@tool, folder: "drafts"), headers: @headers
      draft = response.parsed_body["conversations"].sole
      assert draft["draft"]
      assert_equal new_tool_mail_url(@tool, draft_id: mails_messages(:draft_message).id), draft["url"]

      mails_messages(:inbox_read).update!(folder: "Receipts")
      get tool_mails_path(@tool, folder: "Receipts"), headers: @headers
      assert_equal [ "Your weekly report" ], response.parsed_body["conversations"].map { |conversation| conversation["subject"] }

      get tool_mails_path(@tool, q: "welcome"), headers: @headers
      assert_equal [ "Welcome to Dobase" ], response.parsed_body["conversations"].map { |conversation| conversation["subject"] }
    end

    test "index pages through conversations" do
      30.times do |index|
        @account.messages.create!(message_id: "<bulk-#{index}@example.com>", subject: "Bulk #{index}", from_address: "bulk@example.com",
          folder: "INBOX", read: true, sent_at: 3.days.ago - index.minutes)
      end

      get tool_mails_path(@tool, page: 2), headers: @headers

      body = response.parsed_body
      assert_equal [ 2, 2, 33 ], body.values_at("page", "total_pages", "total_count")
      assert_equal [ "Bulk 27", "Bulk 28", "Bulk 29" ], body["conversations"].map { |conversation| conversation["subject"] }
    end

    test "index answers 404 when the tool has no mail account" do
      unconfigured = Tool.create!(name: "New Mail", tool_type: tool_types(:mail), owner: @user)

      get tool_mails_path(unconfigured), headers: @headers
      assert_response :not_found
      assert_equal "Mail account not configured", response.parsed_body["error"]

      get tool_mails_path(tools(:project_board)), headers: @headers
      assert_response :not_found
    end

    test "show returns the whole conversation, oldest first, without marking it read" do
      message = mails_messages(:inbox_unread)
      reply = @account.messages.create!(message_id: "<reply-001@example.com>", in_reply_to: message.message_id, folder: "Sent",
        subject: "Re: Welcome to Dobase", from_address: "testuser@example.com", from_name: "Test User",
        to_addresses: [ "sender@example.com" ].to_json, cc_addresses: [ "team@example.com" ].to_json,
        body_plain: "Thanks, glad to be here.", read: true, sent_at: 10.minutes.ago)

      get tool_mail_path(@tool, message), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal [ message.id, "thread-001", "Welcome to Dobase" ], body.values_at("id", "thread_id", "subject")
      assert_equal "testuser@example.com", body.dig("account", "email_address")
      assert_equal [ message.id, reply.id ], body["messages"].map { |each| each["id"] }

      first, second = body["messages"]
      assert_equal [ "Welcome to Dobase", "Friendly Sender", "sender@example.com" ], first.values_at("subject", "from_name", "from_address")
      assert_equal [ [ "testuser@example.com" ], [] ], first.values_at("to", "cc")
      assert_equal [ false, false, false, false, false ], first.values_at("read", "starred", "archived", "trashed", "draft")
      assert_equal [ "INBOX", "<msg-001@example.com>", nil ], first.values_at("folder", "message_id", "in_reply_to")
      assert_equal "Welcome to Dobase! We hope you enjoy the platform.", first["body"]
      assert_equal "<p>Welcome to Dobase! We hope you enjoy the platform.</p>", first["body_html"]
      assert_equal [ [], [] ], first.values_at("attachments", "calendar_invites")
      assert_equal tool_mail_url(@tool, message), first["url"]
      assert first["sent_at"].present?

      assert_equal [ [ "team@example.com" ], "<msg-001@example.com>", "Sent" ], second.values_at("cc", "in_reply_to", "folder")
      assert_nil second["body_html"]

      assert_not message.reload.read
      assert_no_enqueued_jobs
    end

    test "show gives the text of HTML-only messages and lists attachments and calendar invites" do
      message = @account.messages.create!(message_id: "<html-only@example.com>", subject: "Launch sync", folder: "INBOX",
        from_address: "boss@example.com", body_html: "<style>p { color: red }</style><p>Hello <b>team</b>,</p><p>See you there.</p>",
        has_attachments: true, sent_at: 5.minutes.ago)
      attachment = message.attachments.create!(filename: "agenda.txt", content_type: "text/plain", file_size: 5)
      attachment.file.attach(io: StringIO.new("hello"), filename: "agenda.txt", content_type: "text/plain")
      message.calendar_invites.create!(uid: "launch-sync", summary: "Launch sync", location: "Room 1", organizer_email: "boss@example.com",
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, status: "pending")

      get tool_mail_path(@tool, message), headers: @headers

      shown = response.parsed_body["messages"].sole
      assert_equal "Hello team,\n\nSee you there.", shown["body"]
      assert_equal [ attachment.id, "agenda.txt", "text/plain", 5 ], shown["attachments"].sole.values_at("id", "filename", "content_type", "file_size")
      assert shown["attachments"].sole["download_url"].present?
      assert_equal [ "Launch sync", "Room 1", "boss@example.com", "pending", false ],
        shown["calendar_invites"].sole.values_at("summary", "location", "organizer_email", "status", "all_day")
    end

    test "show returns drafts as JSON" do
      draft = mails_messages(:draft_message)

      get tool_mail_path(@tool, draft), headers: @headers

      assert_response :success
      shown = response.parsed_body["messages"].sole
      assert shown["draft"]
      assert_equal new_tool_mail_url(@tool, draft_id: draft.id), shown["url"]
    end

    test "read and unread change the flag here and on the mail server" do
      message = mails_messages(:inbox_unread)

      post tool_mail_read_path(@tool, message), headers: @headers, as: :json
      assert_response :success
      assert response.parsed_body["read"]
      assert message.reload.read
      assert_enqueued_with job: ImapSyncJob, args: [ @account.id, "mark_as_read", 101, "INBOX" ]

      delete tool_mail_read_path(@tool, message), headers: @headers, as: :json
      assert_response :success
      assert_not response.parsed_body["read"]
      assert_enqueued_with job: ImapSyncJob, args: [ @account.id, "mark_as_unread", 101, "INBOX" ]
    end

    test "star and unstar change the flag here and on the mail server" do
      message = mails_messages(:inbox_read)

      post tool_mail_star_path(@tool, message), headers: @headers, as: :json
      assert_response :success
      assert response.parsed_body["starred"]
      assert_enqueued_with job: ImapSyncJob, args: [ @account.id, "set_starred", 102, "INBOX", true ]

      delete tool_mail_star_path(@tool, message), headers: @headers, as: :json
      assert_not response.parsed_body["starred"]
      assert_enqueued_with job: ImapSyncJob, args: [ @account.id, "set_starred", 102, "INBOX", false ]
    end

    test "archive and unarchive return the message" do
      message = mails_messages(:inbox_read)

      post tool_mail_archive_path(@tool, message), headers: @headers, as: :json
      assert_response :success
      assert response.parsed_body["archived"]
      assert_enqueued_with job: ImapSyncJob, args: [ @account.id, "mark_as_read", 102, "INBOX" ]

      delete tool_mail_archive_path(@tool, message), headers: @headers, as: :json
      assert_response :success
      assert_not response.parsed_body["archived"]
      assert_not message.reload.archived
    end

    test "tokens can't trash mail, because trashing deletes it on the mail server" do
      message = mails_messages(:inbox_read)

      post tool_mail_trash_path(@tool, message), headers: @headers, as: :json
      assert_response :forbidden

      delete tool_mail_trash_path(@tool, mails_messages(:trashed_message)), headers: @headers, as: :json
      assert_response :forbidden

      assert_not message.reload.trashed
      assert_empty @imap.calls
    end

    test "move puts the message in another folder" do
      message = mails_messages(:inbox_read)

      post tool_mail_move_path(@tool, message), params: { folder: "Receipts" }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Receipts", response.parsed_body["folder"]
      assert_equal "Receipts", message.reload.folder
      assert_enqueued_with job: ImapSyncJob, args: [ @account.id, "move_to_folder", 102, "INBOX", "Receipts" ]
    end

    test "move refuses invalid folder names" do
      post tool_mail_move_path(@tool, mails_messages(:inbox_read)), params: { folder: "Receipts; DROP" }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_equal [ "Invalid folder name" ], response.parsed_body["errors"]
      assert_equal "INBOX", mails_messages(:inbox_read).reload.folder
    end

    test "drafts can be created and partially updated" do
      post tool_mail_drafts_path(@tool), headers: @headers, as: :json, params: {
        to: "friend@example.com, boss@example.com", cc: "team@example.com", subject: "Re: Welcome to Dobase",
        body: "<p>Thanks <b>a lot</b></p><p>Fish &amp; chips?</p>", in_reply_to: "<msg-001@example.com>"
      }

      assert_response :created
      draft = response.parsed_body
      assert_equal [ true, "Drafts", "testuser@example.com" ], draft.values_at("draft", "folder", "from_address")
      assert_equal [ [ "friend@example.com", "boss@example.com" ], [ "team@example.com" ] ], draft.values_at("to", "cc")
      assert_equal [ "Re: Welcome to Dobase", "Thanks a lot\n\nFish & chips?", "<p>Thanks <b>a lot</b></p><p>Fish &amp; chips?</p>" ],
        draft.values_at("subject", "body", "body_html")
      assert_equal "<msg-001@example.com>", draft["in_reply_to"]
      assert_enqueued_with job: SyncDraftJob, args: [ draft["id"] ]
      assert_equal "thread-001", ::Mails::Message.find(draft["id"]).thread_id

      patch tool_mail_draft_path(@tool, draft["id"]), params: { subject: "Thanks!" }, headers: @headers, as: :json

      assert_response :success
      updated = response.parsed_body
      assert_equal "Thanks!", updated["subject"]
      assert_equal [ [ "friend@example.com", "boss@example.com" ], "<p>Thanks <b>a lot</b></p><p>Fish &amp; chips?</p>" ], updated.values_at("to", "body_html")
      assert_enqueued_jobs 2, only: SyncDraftJob
    end

    test "draft update only finds drafts" do
      patch tool_mail_draft_path(@tool, mails_messages(:inbox_read)), params: { subject: "Nope" }, headers: @headers, as: :json

      assert_response :not_found
      assert_equal "Your weekly report", mails_messages(:inbox_read).reload.subject
    end

    test "send delivers the email and returns the recipients" do
      post tool_mails_path(@tool), headers: @headers, as: :json, params: {
        to: "friend@example.com", cc: "team@example.com", bcc: "archive@example.com", subject: "Hello", body: "<p>Hi <b>there</b></p>"
      }

      assert_response :created
      assert_equal({ "to" => [ "friend@example.com" ], "cc" => [ "team@example.com" ], "bcc" => [ "archive@example.com" ], "subject" => "Hello" },
        response.parsed_body)

      email = @smtp.sent.sole
      assert_equal [ [ "friend@example.com" ], [ "team@example.com" ], [ "archive@example.com" ] ], email.values_at(:to, :cc, :bcc)
      assert_equal [ "Hello", "Hi there", "<p>Hi <b>there</b></p>" ], email.values_at(:subject, :body, :body_html)
      assert_nil email[:attachments]
      assert_nil email[:in_reply_to]
    end

    test "send replies to the message whose message_id is in_reply_to" do
      post tool_mails_path(@tool), headers: @headers, as: :json, params: {
        to: "reports@example.com", subject: "Re: Your weekly report", body: "<p>Thanks</p>", in_reply_to: mails_messages(:inbox_read).message_id
      }

      assert_response :created
      assert_equal mails_messages(:inbox_read).message_id, @smtp.sent.sole[:in_reply_to]
    end

    test "sending a draft deletes the draft" do
      draft = mails_messages(:draft_message)

      post tool_mails_path(@tool), headers: @headers, as: :json, params: {
        to: "recipient@example.com", subject: "Draft email", body: "<p>This is a draft message.</p>", draft_id: draft.id
      }

      assert_response :created
      assert_equal 1, @smtp.sent.size
      assert_not ::Mails::Message.exists?(draft.id)
      assert_equal [ [ :delete_draft, nil ] ], @imap.calls
    end

    test "send refuses invalid addresses without sending anything" do
      post tool_mails_path(@tool), params: { to: "friend@example.com", bcc: "not-an-address", subject: "Hi", body: "<p>Hi</p>" },
        headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_equal [ "Invalid email address: not-an-address" ], response.parsed_body["errors"]
      assert_empty @smtp.sent
    end

    test "send reports SMTP failures" do
      @smtp.failure = "Failed to send email: 550 Mailbox unavailable"

      post tool_mails_path(@tool), params: { to: "friend@example.com", subject: "Hi", body: "<p>Hi</p>" }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_equal [ "Failed to send email: 550 Mailbox unavailable" ], response.parsed_body["errors"]
    end

    test "send forwards attachments from this account's own mail" do
      attachment = mails_messages(:inbox_unread).attachments.create!(filename: "report.txt", content_type: "text/plain", file_size: 5)
      attachment.file.attach(io: StringIO.new("hello"), filename: "report.txt", content_type: "text/plain")

      post tool_mails_path(@tool), headers: @headers, as: :json, params: {
        to: "friend@example.com", subject: "Fwd: Welcome", body: "<p>FYI</p>", forward_attachment_ids: [ attachment.id ]
      }

      assert_response :created
      assert_equal [ attachment.file.blob ], @smtp.sent.sole[:attachments]
    end

    test "sync starts a sync and reports its status" do
      post tool_sync_path(@tool), headers: @headers, as: :json

      assert_response :success
      assert_equal "syncing", response.parsed_body["status"]
      assert_enqueued_with job: SyncEmailsJob, args: [ @account.id ]

      get tool_sync_path(@tool), headers: @headers
      assert_equal "syncing", response.parsed_body["status"]
      assert response.parsed_body["last_synced_at"].present?
    end

    test "contacts match saved contacts and senders" do
      @account.record_contact("frida@example.com", "Frida")

      get tool_mails_contacts_path(@tool, q: "fri"), headers: @headers

      assert_response :success
      assert_equal [ "frida@example.com", "sender@example.com" ], response.parsed_body.map { |contact| contact["email_address"] }
    end

    test "read-only tokens can read mail but not change or send it" do
      headers = api_headers(@user, permission: "read")
      message = mails_messages(:inbox_unread)

      get tool_mails_path(@tool), headers: headers
      assert_response :success
      get tool_mail_path(@tool, message), headers: headers
      assert_response :success

      post tool_mail_read_path(@tool, message), headers: headers, as: :json
      assert_response :forbidden
      assert_equal "This access token is read-only", response.parsed_body["error"]

      post tool_mails_path(@tool), params: { to: "friend@example.com", subject: "Hi", body: "<p>Hi</p>" }, headers: headers, as: :json
      assert_response :forbidden

      post tool_mail_drafts_path(@tool), params: { subject: "Hi" }, headers: headers, as: :json
      assert_response :forbidden

      assert_not message.reload.read
      assert_empty @smtp.sent
    end

    test "tokens can't delete mail for good, empty the trash, bulk edit, compose in the browser or touch the account" do
      trashed = mails_messages(:trashed_message)

      delete tool_mail_path(@tool, trashed), headers: @headers, as: :json
      assert_response :forbidden
      assert_equal "This action isn't available to access tokens", response.parsed_body["error"]

      delete tool_empty_trash_path(@tool), headers: @headers, as: :json
      assert_response :forbidden

      post tool_bulk_path(@tool), params: { message_ids: [ trashed.id ], action_type: "delete" }, headers: @headers, as: :json
      assert_response :forbidden

      get new_tool_mail_path(@tool), headers: @headers
      assert_response :forbidden

      get new_tool_mails_account_path(@tool), headers: @headers
      assert_response :forbidden

      post tool_mails_account_path(@tool), params: { mails_account: { imap_host: "imap.evil.example" } }, headers: @headers, as: :json
      assert_response :forbidden

      patch tool_mails_account_path(@tool), params: { mails_account: { imap_host: "imap.evil.example" } }, headers: @headers, as: :json
      assert_response :forbidden

      post test_connection_tool_mails_account_path(@tool), headers: @headers, as: :json
      assert_response :forbidden

      assert ::Mails::Message.exists?(trashed.id)
      assert_equal "imap.example.com", @account.reload.imap_host
      assert_empty @imap.calls
    end

    test "mail from another tool is not found" do
      other = Tool.create!(name: "Other Mail", tool_type: tool_types(:mail), owner: @user)
      other.create_mail_account!(email_address: "other@example.com", imap_host: "imap.example.com", smtp_host: "smtp.example.com",
        username: "other@example.com", password: "secret", smtp_auth: "plain")
      message = mails_messages(:inbox_unread)

      get tool_mail_path(other, message), headers: @headers
      assert_response :not_found

      post tool_mail_star_path(other, message), headers: @headers, as: :json
      assert_response :not_found

      patch tool_mail_draft_path(other, mails_messages(:draft_message)), params: { subject: "Nope" }, headers: @headers, as: :json
      assert_response :not_found

      # A draft from another tool is left alone (sending still goes through that tool's own account).
      post tool_mails_path(other), params: { to: "friend@example.com", subject: "Hi", body: "<p>Hi</p>", draft_id: mails_messages(:draft_message).id },
        headers: @headers, as: :json
      assert_response :created
      assert ::Mails::Message.exists?(mails_messages(:draft_message).id)

      assert_not message.reload.starred
      assert_not message.trashed
      assert_empty @imap.calls
    end

    test "tools without a mail account answer 404" do
      board = tools(:project_board)
      message = mails_messages(:inbox_unread)

      post tool_mail_read_path(board, message), headers: @headers, as: :json
      assert_response :not_found

      post tool_mail_move_path(board, message), params: { folder: "Receipts" }, headers: @headers, as: :json
      assert_response :not_found

      post tool_mail_drafts_path(board), params: { subject: "Hi" }, headers: @headers, as: :json
      assert_response :not_found
      assert_equal "Mail account not configured", response.parsed_body["error"]

      post tool_mails_path(board), params: { to: "friend@example.com", subject: "Hi", body: "<p>Hi</p>" }, headers: @headers, as: :json
      assert_response :not_found

      post tool_sync_path(board), headers: @headers, as: :json
      assert_response :not_found

      get tool_mails_contacts_path(board, q: "friend"), headers: @headers
      assert_response :not_found

      assert_empty @smtp.sent
      assert_not message.reload.read
    end

    test "mail in tools the user can't access is forbidden" do
      headers = api_headers(users(:two))

      get tool_mails_path(@tool), headers: headers
      assert_response :forbidden

      post tool_mail_read_path(@tool, mails_messages(:inbox_unread)), headers: headers, as: :json
      assert_response :forbidden

      post tool_mails_path(@tool), params: { to: "friend@example.com", subject: "Hi", body: "<p>Hi</p>" }, headers: headers, as: :json
      assert_response :forbidden
      assert_empty @smtp.sent
    end

    private

    def fake_service(service, fake)
      service.singleton_class.define_method(:new) { |*| fake }
      (@faked_services ||= []) << service
    end
  end
end

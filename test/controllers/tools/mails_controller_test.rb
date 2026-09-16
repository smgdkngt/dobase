# frozen_string_literal: true

require "test_helper"

module Tools
  class MailsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_mail)
      @account = mails_accounts(:primary)
    end

    test "index renders inbox with messages" do
      get tool_mails_path(@tool)
      assert_response :success
      assert_includes response.body, "Welcome to Dobase"
      assert_includes response.body, "Your weekly report"
    end

    test "index with folder=starred shows starred messages" do
      get tool_mails_path(@tool, folder: "starred")
      assert_response :success
      assert_includes response.body, "Important info"
    end

    test "index with folder=trash shows trashed messages" do
      get tool_mails_path(@tool, folder: "trash")
      assert_response :success
      assert_includes response.body, "Old spam"
    end

    test "index with folder=archive shows archived messages" do
      get tool_mails_path(@tool, folder: "archive")
      assert_response :success
      assert_includes response.body, "Archived conversation"
    end

    test "index takes the same number of queries however many conversations there are" do
      account = @tool.mail_account
      add_threads = ->(count, offset) do
        count.times do |index|
          account.messages.create!(message_id: "many-#{offset + index}@example.com", folder: "INBOX", subject: "Many #{offset + index}",
            from_address: "many@example.com", sent_at: (offset + index).hours.ago)
        end
      end

      add_threads.call(2, 0)
      few = count_queries { get tool_mails_path(@tool) }
      add_threads.call(20, 2)
      many = count_queries { get tool_mails_path(@tool) }

      assert_response :success
      assert_equal few, many
    end

    test "show renders message detail and marks read" do
      msg = mails_messages(:inbox_unread)
      assert_not msg.read

      get tool_mail_path(@tool, msg)
      assert_response :success
      assert_includes response.body, "Welcome to Dobase"
      assert msg.reload.read
    end

    test "show keeps remote content out of an email until the reader asks for it" do
      msg = mails_messages(:inbox_unread)
      msg.update!(body_html: %(<style>body { background: url(https://tracker.example/open.gif) }</style><p>Hi</p><img src="https://tracker.example/pixel.gif">))

      get tool_mail_path(@tool, msg)

      assert_includes response.body, "Images are hidden"
      shown = css_select("iframe[data-email-frame-target='frame']").first["srcdoc"]
      assert_includes shown, %(content="default-src 'none'; img-src data: cid:;)
      assert_not_includes shown, "https://tracker.example/pixel.gif"

      on_request = css_select("[data-email-frame-full-srcdoc-value]").first["data-email-frame-full-srcdoc-value"]
      assert_not_includes on_request, "Content-Security-Policy"
      assert_includes on_request, "https://tracker.example/pixel.gif"
    end

    test "show offers to load images when only CSS pulls in remote content" do
      msg = mails_messages(:inbox_unread)
      msg.update!(body_html: %(<style>body { background: url('https://tracker.example/open.gif') }</style><p>Hi</p>))

      get tool_mail_path(@tool, msg)

      assert_includes response.body, "Images are hidden"
    end

    test "the list says how many messages it has" do
      get tool_mails_path(@tool, folder: "trash")
      assert_select "span", text: "1 message"

      get tool_mails_path(@tool)
      assert_select "span", text: "3 messages"
    end

    test "the compose form is titled after what it's for" do
      message = mails_messages(:inbox_read)
      {
        new_tool_mail_path(@tool) => "New Message",
        new_tool_mail_path(@tool, reply_to: message.id) => "Reply",
        new_tool_mail_path(@tool, reply_to: message.id, reply_all: true) => "Reply All",
        new_tool_mail_path(@tool, forward: message.id) => "Forward",
        new_tool_mail_path(@tool, draft_id: mails_messages(:draft_message).id) => "Edit Draft"
      }.each do |path, heading|
        get path

        assert_select "h1", heading
        assert_select "title", "#{heading} - My Mail - #{Rails.application.config.x.app.name}"
      end
    end

    test "show redirects drafts to the compose form" do
      draft = mails_messages(:draft_message)
      get tool_mail_path(@tool, draft)
      assert_redirected_to new_tool_mail_path(@tool, draft_id: draft.id)
    end

    test "show offers to add a pending invite to the user's writable calendars" do
      msg = mails_messages(:inbox_unread)
      invite = msg.calendar_invites.create!(uid: "planning@example.com", method: "REQUEST", summary: "Quarterly planning",
                                            starts_at: Time.utc(2026, 10, 1, 9), ends_at: Time.utc(2026, 10, 1, 10))
      calendars_accounts(:icloud_account).calendars.create!(name: "Holidays", remote_id: "/holidays/", read_only: true)
      calendars_accounts(:pending_account).calendars.create!(name: "Theirs", remote_id: "/theirs/")

      get tool_mail_path(@tool, msg)

      assert_response :success
      assert_select "h4", text: "Quarterly planning"
      assert_select "form[action=?] input[name=invite_id][value=?]", tool_calendar_invites_path(tools(:my_calendar)), invite.id.to_s
      assert_equal [ "My Calendar - Personal", "My Calendar - Work" ], css_select("select[name=calendar_id] option").map(&:text)
    end

    test "show marks a cancelled invitation and points to the event still in the calendar" do
      calendar = calendars_calendars(:personal)
      starts_at = Time.utc(2026, 10, 1, 9)
      event = calendar.events.create!(uid: "standup@example.com", summary: "Standup", starts_at: starts_at, ends_at: starts_at + 1.hour)
      mails_messages(:inbox_read).calendar_invites.create!(uid: "standup@example.com", method: "REQUEST", status: "accepted", summary: "Standup",
                                                           starts_at: starts_at, ends_at: starts_at + 1.hour, added_to_calendar: calendar, created_event: event)
      msg = mails_messages(:inbox_unread)
      msg.calendar_invites.create!(uid: "standup@example.com", method: "CANCEL", status: "cancelled", summary: "Standup",
                                   starts_at: starts_at, ends_at: starts_at + 1.hour)

      get tool_mail_path(@tool, msg)

      assert_response :success
      assert_includes response.body, "This event has been cancelled."
      assert_select "a[href=?]", tool_calendar_path(tools(:my_calendar), week_start: starts_at.to_date), text: /View in Calendar/
      assert_select "input[name=invite_id]", count: 0
    end

    test "show leaves out replies to the user's own invitations" do
      msg = mails_messages(:inbox_unread)
      msg.calendar_invites.create!(uid: "planning@example.com", method: "REPLY", summary: "Quarterly planning",
                                   starts_at: Time.utc(2026, 10, 1, 9), ends_at: Time.utc(2026, 10, 1, 10))

      get tool_mail_path(@tool, msg)

      assert_response :success
      assert_select "h3", text: "Calendar Invitation", count: 0
    end

    test "show links an accepted invite to its week in the calendar" do
      msg = mails_messages(:inbox_unread)
      msg.calendar_invites.create!(uid: "planning@example.com", method: "REQUEST", summary: "Quarterly planning", status: "accepted",
                                   starts_at: Time.utc(2026, 10, 1, 9), ends_at: Time.utc(2026, 10, 1, 10),
                                   added_to_calendar: calendars_calendars(:personal), created_event: calendars_events(:meeting))

      get tool_mail_path(@tool, msg)

      assert_select "a[href=?]", tool_calendar_path(tools(:my_calendar), week_start: "2026-10-01"), text: "View in Calendar"
      assert_select "select[name=calendar_id]", count: 0
    end

    test "show still renders a message whose invite has no title or times" do
      msg = mails_messages(:inbox_unread)
      msg.calendar_invites.create!(uid: "untimed@example.com", method: "REQUEST", summary: "")

      get tool_mail_path(@tool, msg)

      assert_response :success
      assert_select "h4", text: "(No title)"
    end

    test "create with an invalid address shows the compose form again" do
      post tool_mails_path(@tool), params: { to: "not-an-address", subject: "Hi", body: "<p>Hi</p>" }
      assert_response :unprocessable_entity
      assert_includes response.body, "Invalid email address: not-an-address"
    end

    test "create sends to recipients written with their name" do
      deliveries = capture_smtp_deliveries do
        post tool_mails_path(@tool), params: {
          to: "Friendly Sender <sender@example.com>", cc: "Reports Bot <reports@example.com>, boss@example.com", subject: "Hello", body: "<p>Hi</p>"
        }
      end

      assert_redirected_to tool_mails_path(@tool, folder: "sent")
      assert_equal [ "sender@example.com", "reports@example.com", "boss@example.com" ], deliveries.sole[:recipients]
      assert_match "To: Friendly Sender <sender@example.com>", deliveries.sole[:message]
    end

    test "create refuses a name without a valid address" do
      [ "Friendly Sender <sender>", "Friendly Sender <sender@example.com" ].each do |recipient|
        post tool_mails_path(@tool), params: { to: recipient, subject: "Hi", body: "<p>Hi</p>" }

        assert_response :unprocessable_entity
        assert_includes response.body, "Invalid email address: #{ERB::Util.html_escape(recipient)}"
      end
    end

    test "a reply goes out in the conversation it answers" do
      original = mails_messages(:inbox_read)
      original.update!(references: "<msg-000@example.com>")

      get new_tool_mail_path(@tool, reply_to: original.id)
      assert_select "input[name=in_reply_to][value=?]", original.message_id

      deliveries = capture_smtp_deliveries do
        post tool_mails_path(@tool), params: {
          to: "reports@example.com", subject: "Re: Your weekly report", body: "<p>Thanks</p>", in_reply_to: original.message_id
        }
      end

      assert_redirected_to tool_mails_path(@tool, folder: "sent")
      assert_match "In-Reply-To: <msg-002@example.com>", deliveries.sole[:message]
      assert_match(/References: <msg-000@example.com>\s+<msg-002@example.com>/, deliveries.sole[:message])

      reply = @account.messages.sent.find_by!(subject: "Re: Your weekly report")
      assert_equal original.message_id, reply.in_reply_to
      assert_includes original.conversation, reply
    end

    test "a reply that can't be sent is still a reply when the form comes back" do
      original = mails_messages(:inbox_read)

      post tool_mails_path(@tool), params: {
        to: "not-an-address", subject: "Re: Your weekly report", body: "<p>Thanks</p>", in_reply_to: original.message_id
      }

      assert_response :unprocessable_entity
      assert_select "input[name=in_reply_to][value=?]", original.message_id
      assert_select "h1", "Reply"
    end

    test "index with search query filters messages" do
      get tool_mails_path(@tool, q: "Welcome")
      assert_response :success
      assert_includes response.body, "Welcome to Dobase"
    end

    test "index redirects to account setup when no account" do
      tool_no_mail = Tool.create!(name: "Empty Mail", tool_type: tool_types(:mail), owner: users(:one))
      get tool_mails_path(tool_no_mail)
      assert_redirected_to new_tool_mails_account_path(tool_no_mail)

      get new_tool_mail_path(tool_no_mail)
      assert_redirected_to new_tool_mails_account_path(tool_no_mail)
    end

    test "collaborators see that the owner hasn't connected a mail account yet" do
      tool = Tool.create!(name: "Team Mail", tool_type: tool_types(:mail), owner: users(:one), sidebar_position: -1)
      tool.collaborators.create!(user: users(:two), role: "collaborator")
      sign_in_as users(:two)

      get root_path
      3.times { follow_redirect! if response.redirect? }

      assert_response :success
      assert_equal tool_mails_path(tool), path
      assert_select "h1", "Team Mail"
      assert_select "div", text: "The owner of Team Mail hasn't connected a mail account yet. Once they have, the mail shows up here."

      get new_tool_mail_path(tool)
      assert_response :success
      assert_select "div", text: /hasn't connected a mail account yet/
    end

    test "destroy from inbox trashes message" do
      msg = mails_messages(:inbox_read)
      delete tool_mail_path(@tool, msg)
      assert msg.reload.trashed
    end

    test "destroy from trash permanently deletes message" do
      msg = mails_messages(:trashed_message)
      assert_difference "::Mails::Message.count", -1 do
        delete tool_mail_path(@tool, msg)
      end
    end

    test "requires authentication" do
      sign_out
      get tool_mails_path(@tool)
      assert_redirected_to new_session_path
    end

    test "create forwards attachments from this account only" do
      own_attachment = attachment_on(mails_messages(:inbox_read), "report.pdf")
      foreign_attachment = attachment_on(mails_messages(:other_inbox), "agenda.pdf")

      deliveries = capture_sent_mail do
        post tool_mails_path(@tool), params: {
          to: "friend@example.com", subject: "Fwd: files", body: "<p>See attached</p>",
          forward_attachment_ids: [ own_attachment.id, foreign_attachment.id ]
        }
      end

      assert_redirected_to tool_mails_path(@tool, folder: "sent")
      assert_equal 1, deliveries.size
      assert_equal [ own_attachment.file.blob ], deliveries.first[:attachments]
    end

    private

    def attachment_on(message, filename)
      message.attachments.create!(filename: filename, content_type: "application/pdf", file_size: 6).tap do |attachment|
        attachment.file.attach(io: StringIO.new("%PDF-1"), filename: filename, content_type: "application/pdf")
      end
    end

    # Records what would have been sent instead of talking to an SMTP server.
    def capture_sent_mail
      deliveries = []
      SmtpSendService.alias_method :send_email_without_capture, :send_email
      SmtpSendService.define_method(:send_email) { |**options| deliveries << options }
      yield
      deliveries
    ensure
      SmtpSendService.alias_method :send_email, :send_email_without_capture
      SmtpSendService.remove_method :send_email_without_capture
    end

    def count_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:cached] || payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
  end
end

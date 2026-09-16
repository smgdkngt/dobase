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

    test "index with search query filters messages" do
      get tool_mails_path(@tool, q: "Welcome")
      assert_response :success
      assert_includes response.body, "Welcome to Dobase"
    end

    test "index redirects to account setup when no account" do
      tool_no_mail = Tool.create!(name: "Empty Mail", tool_type: tool_types(:mail), owner: users(:one))
      get tool_mails_path(tool_no_mail)
      assert_redirected_to new_tool_mails_account_path(tool_no_mail)
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
  end
end

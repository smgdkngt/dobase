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

    test "the mail page stops refreshing while the server turns the login down" do
      get tool_mails_path(@tool)
      assert_select "[data-mail-refresh-interval-value='60']"

      @account.mark_sync_error!(::Mails::Account::AUTHENTICATION_FAILED)
      get tool_mails_path(@tool)
      assert_select "[data-mail-refresh-interval-value='0']"
      assert_includes response.body, "The mail server didn&#39;t accept the username or password"
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

    test "folders show by the names they were given, and are opened and moved to by the server's names" do
      @account.update!(synced_folders: [ "INBOX", "Sent", "B&APw-ro", "Facturen &- bonnen" ].to_json)

      get tool_mail_path(@tool, mails_messages(:inbox_read))

      assert_select "nav.mail-folder-rail a[href=?]", tool_mails_path(@tool, folder: "B&APw-ro"), text: "Büro"
      assert_select "nav.mail-folder-rail a[href=?]", tool_mails_path(@tool, folder: "Facturen &- bonnen"), text: "Facturen & bonnen"
      assert_select "#move-to-menu form" do
        assert_select "input[name=folder][value=?]", "B&APw-ro"
        assert_select "button", text: "Büro"
        assert_select "button", text: "Facturen & bonnen"
      end
      assert_select "#bulk-move-menu button[data-folder=?]", "B&APw-ro", text: "Büro"
      assert_not_includes response.body, ">B&amp;APw-ro<"

      get tool_mails_path(@tool, folder: "B&APw-ro")

      assert_select ".mail-folder-picker button span", text: "Büro"
      assert_includes response.body, "No messages in Büro"
    end

    test "a new folder gets a plain name" do
      [ "Work (old)", "Receipts*", "Büro", "a" * 101, "" ].each do |name|
        post tool_folder_path(@tool), params: { folder_name: name }

        assert_redirected_to tool_mails_path(@tool)
        assert_equal "Invalid folder name.", flash[:alert], name
      end
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

    test "show leaves out the text of scripts and the title" do
      msg = mails_messages(:inbox_unread)
      msg.update!(body_html: %(<html><head><title>Notification</title></head><body><p>Hi</p><script type="application/ld+json">{"@context": "http://schema.org"}</script></body></html>))

      get tool_mail_path(@tool, msg)

      shown = css_select("iframe[data-email-frame-target='frame']").first["srcdoc"]
      assert_includes shown, "<p>Hi</p>"
      assert_not_includes shown, "schema.org"
      assert_not_includes shown, "Notification"
    end

    test "show keeps text that reads like an event handler, and no event handlers" do
      msg = mails_messages(:inbox_unread)
      msg.update!(body_html: %(<p>Totaal onkosten = 45,00 euro</p><p>De <b>online = "ja"</b> optie</p><p onclick="alert(1)">Hi</p><img src="https://example.com/a.png" onerror=alert(2) onload='alert(3)'>))

      get tool_mail_path(@tool, msg)

      frame = css_select("iframe[data-email-frame-target='frame']").first
      [ frame["srcdoc"], frame.parent.parent["data-email-frame-full-srcdoc-value"] ].each do |shown|
        assert_includes shown, "<p>Totaal onkosten = 45,00 euro</p>"
        assert_includes shown, %(<b>online = "ja"</b>)
        assert_not_includes shown, "alert"
        assert_empty Nokogiri::HTML5(shown).css("*").flat_map { |element| element.attribute_nodes.map(&:name) }.grep(/\Aon/i)
      end
    end

    test "show puts the pictures a message carries in its text, and lists only the other attachments" do
      msg = mails_messages(:inbox_unread)
      msg.update!(body_html: %(<p>Look</p><img src="cid:logo@example.com">))
      logo = msg.attachments.create!(filename: "logo.png", content_type: "image/png", file_size: 3, content_id: "logo@example.com")
      logo.file.attach(io: StringIO.new("PNG"), filename: "logo.png", content_type: "image/png")
      report = msg.attachments.create!(filename: "report.pdf", content_type: "application/pdf", file_size: 3)
      report.file.attach(io: StringIO.new("PDF"), filename: "report.pdf", content_type: "application/pdf")

      get tool_mail_path(@tool, msg)

      shown = css_select("iframe[data-email-frame-target='frame']").first["srcdoc"]
      assert_includes shown, %(src="data:image/png;base64,#{Base64.strict_encode64("PNG")}")
      assert_includes response.body, "1 attachment"
      assert_includes response.body, "report.pdf"
      assert_not_includes response.body, "logo.png"
      assert_select "button span[title='1 attachment'] svg[aria-label='1 attachment']", 1, "a paperclip in the message's header"
    end

    test "show leaves the paperclip out of the header of a message without attachments" do
      get tool_mail_path(@tool, mails_messages(:inbox_unread))

      assert_select "button span[title$='attachment']", 0
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

    test "the compose form sits next to the folder it was started from, which doesn't refresh under it" do
      message = mails_messages(:inbox_read)
      get new_tool_mail_path(@tool, reply_to: message.id, folder: "inbox")

      assert_select ".mail-layout.mail-detail-open[data-mail-refresh-interval-value='0']"
      assert_select ".mail-list-item.selected", text: /#{message.subject}/
      assert_select "#mail-content form[action='#{tool_mails_path(@tool)}']"
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

    test "show gives an all-day invite its own dates, west of UTC too" do
      users(:one).update!(timezone: "Pacific Time (US & Canada)")
      msg = mails_messages(:inbox_unread)
      msg.calendar_invites.create!(uid: "offsite@example.com", method: "REQUEST", summary: "Offsite", status: "accepted", all_day: true,
                                   starts_at: Time.utc(2026, 10, 1), ends_at: Time.utc(2026, 10, 3),
                                   added_to_calendar: calendars_calendars(:personal), created_event: calendars_events(:meeting))

      get tool_mail_path(@tool, msg)

      assert_select "p", text: /Thursday, October 1, 2026\s+– Friday, October 2, 2026/
      assert_not_includes response.body, "September 30"
      assert_select "a[href=?]", tool_calendar_path(tools(:my_calendar), week_start: "2026-10-01"), text: "View in Calendar"
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
      deliveries = capture_smtp_deliveries_in_the_background do
        post tool_mails_path(@tool), params: {
          to: "Friendly Sender <sender@example.com>", cc: "Reports Bot <reports@example.com>, boss@example.com", subject: "Hello", body: "<p>Hi</p>"
        }
      end

      assert_redirected_to tool_mail_path(@tool, @account.messages.sent.find_by!(subject: "Hello"), folder: "inbox")
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

      deliveries = capture_smtp_deliveries_in_the_background do
        post tool_mails_path(@tool), params: {
          to: "reports@example.com", subject: "Re: Your weekly report", body: "<p>Thanks</p>", in_reply_to: original.message_id
        }
      end

      reply = @account.messages.sent.find_by!(subject: "Re: Your weekly report")
      assert_redirected_to tool_mail_path(@tool, original, folder: "inbox")
      assert_match "In-Reply-To: <msg-002@example.com>", deliveries.sole[:message]
      assert_match(/References: <msg-000@example.com>\s+<msg-002@example.com>/, deliveries.sole[:message])
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
      tool = Tool.create!(name: "Team Mail", tool_type: tool_types(:mail), owner: users(:one))
      # First in this collaborator's own sidebar, so the dashboard lands on it.
      tool.collaborators.create!(user: users(:two), role: "collaborator").update!(sidebar_position: -1)
      sign_in_as users(:two)
      # As a phone gets it; for a wide window the dashboard goes to the workspace
      cookies[:workspace] = "off"

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

    test "a draft reply shows as not sent in its conversation, and replying continues it" do
      original = mails_messages(:inbox_read)
      draft = mails_messages(:draft_message)
      original.update!(thread_id: "lunch-plans")
      draft.update!(in_reply_to: original.message_id, thread_id: "lunch-plans")

      get tool_mail_path(@tool, original)

      assert_select ".badge", text: "Draft"
      assert_select ".mail-draft-note", text: /Not sent yet/
      assert_select ".mail-draft-note a[href=?]", new_tool_mail_path(@tool, draft_id: draft.id, folder: "inbox")
      assert_select "a[href=?]", new_tool_mail_path(@tool, reply_to: original.id, folder: "inbox"), text: /Continue your reply/
    end

    test "a draft in the trash is out of its conversation, and opens there as mail that isn't written on" do
      original = mails_messages(:inbox_read)
      draft = mails_messages(:draft_message)
      original.update!(thread_id: "lunch-plans")
      draft.update!(in_reply_to: original.message_id, thread_id: "lunch-plans")
      draft.move_to_trash!

      get tool_mail_path(@tool, original)

      assert_select ".badge", text: "Draft", count: 0
      assert_select "a[href=?]", new_tool_mail_path(@tool, reply_to: original.id, folder: "inbox"), text: /Click to reply/

      get tool_mail_path(@tool, draft, folder: "trash")

      assert_response :success
      assert_select ".badge", text: "Draft"
      assert_select ".mail-draft-note", count: 0
      assert_select ".mail-list-item a[href=?]", tool_mail_path(@tool, draft, folder: "trash")
    end

    test "a draft discarded in its conversation leaves the conversation open" do
      original = mails_messages(:inbox_read)
      draft = mails_messages(:draft_message)
      original.update!(thread_id: "lunch-plans")
      draft.update!(in_reply_to: original.message_id, thread_id: "lunch-plans")

      delete tool_mail_path(@tool, draft, from: "conversation", folder: "inbox")

      assert_redirected_to tool_mail_path(@tool, original, folder: "inbox")
      assert_not ::Mails::Message.exists?(draft.id)
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

      assert_redirected_to tool_mail_path(@tool, @account.messages.sent.find_by!(subject: "Fwd: files"), folder: "inbox")
      assert_equal 1, deliveries.size
      assert_equal [ own_attachment.file.blob ], deliveries.first[:attachments]
    end

    test "sent mail has a text part with the paragraphs of its HTML" do
      deliveries = capture_sent_mail do
        post tool_mails_path(@tool), params: { to: "friend@example.com", subject: "Plans", body: "<p>Hi,</p><p>Thursday works.</p>" }
      end

      assert_equal "<p>Hi,</p><p>Thursday works.</p>", deliveries.first[:body_html]
      assert_equal "Hi,\n\nThursday works.", deliveries.first[:body]
    end

    test "a reply from the compose page quotes the original below the editor, not in it" do
      original = mails_messages(:inbox_read)
      original.update!(from_name: "Ann <Lee>", body_html: "<p>Lunch?</p>")

      get new_tool_mail_path(@tool, reply_to: original.id)

      assert_equal "", css_select("input[type=hidden][name=body]").first["value"]
      assert_select "input[type=hidden][name=quoted_message_id][value=?]", original.id.to_s
      assert_select ".compose-quote", text: /Ann <Lee> <#{original.from_address}> wrote:/
    end

    test "a reply goes out with the mail it answers quoted as it is, and its pictures" do
      original = mails_messages(:inbox_read)
      original.update!(body_html: %(<table style="background: url('https://example.com/bg.png')"><tr><td><img src="cid:logo@example.com">Ann</td></tr></table>))
      logo = original.attachments.create!(filename: "logo.png", content_type: "image/png", file_size: 3, content_id: "logo@example.com")
      logo.file.attach(io: StringIO.new("PNG"), filename: "logo.png", content_type: "image/png")

      deliveries = capture_smtp_deliveries_in_the_background do
        post tool_mails_path(@tool), params: {
          to: "reports@example.com", subject: "Re: Lunch", body: "<p>Sure</p>", in_reply_to: original.message_id, quoted_message_id: original.id
        }
      end

      sent = Mail.new(deliveries.sole[:message])
      html = sent.html_part.decoded
      assert_match %r{<p[^>]*>Sure</p><p[^>]*>On .*wrote:</p><blockquote}, html
      assert_includes html, %(background: url('https://example.com/bg.png'))
      assert_includes html, %(src="cid:quote-#{logo.id}@dobase")
      picture = sent.attachments.sole
      assert_equal [ "logo.png", "<quote-#{logo.id}@dobase>", "PNG" ], [ picture.filename, picture.content_id, picture.decoded ]
      assert_match "> Ann", sent.text_part.decoded

      copy = @account.messages.sent.find_by!(subject: "Re: Lunch")
      assert_includes copy.body_html, "wrote:"
      assert_equal [ "quote-#{logo.id}@dobase" ], copy.attachments.map(&:content_id)
    end

    # A job runs in the time zone it was queued in (ActiveJob), which is the sender's

    test "a reply says when the mail it answers was sent in the sender's time zone, as the compose page did" do
      users(:one).update!(timezone: "Amsterdam")
      original = mails_messages(:inbox_read)
      original.update!(sent_at: Time.utc(2026, 9, 29, 8, 23))

      get new_tool_mail_path(@tool, reply_to: original.id)
      assert_select ".compose-quote", text: /On Tue, Sep 29, 2026 at 10:23 AM, Reports Bot/

      deliveries = capture_smtp_deliveries_in_the_background do
        post tool_mails_path(@tool), params: {
          to: "reports@example.com", subject: "Re: Lunch", body: "<p>Sure</p>", in_reply_to: original.message_id, quoted_message_id: original.id
        }
      end

      sent = Mail.new(deliveries.sole[:message])
      assert_includes sent.html_part.decoded, "On Tue, Sep 29, 2026 at 10:23 AM, Reports Bot"
      assert_includes sent.text_part.decoded, "On Tue, Sep 29, 2026 at 10:23 AM, Reports Bot"
      assert_includes @account.messages.sent.find_by!(subject: "Re: Lunch").body_html, "On Tue, Sep 29, 2026 at 10:23 AM, Reports Bot"
    end

    test "a draft on the server says when the mail it answers was sent in the time zone of whoever saved it" do
      users(:one).update!(timezone: "Amsterdam")
      original = mails_messages(:inbox_read)
      original.update!(sent_at: Time.utc(2026, 9, 29, 8, 23))
      server = FakeImapServer.new(folders: [ "INBOX", "Drafts" ])

      connect_to_imap(server) do
        perform_enqueued_jobs(only: SyncDraftJob) do
          post tool_mail_drafts_path(@tool), params: { to: "reports@example.com", subject: "Re: Lunch", body: "<p>Sure</p>", in_reply_to: original.message_id, quoted_message_id: original.id }
        end
      end

      assert_includes Mail.new(server.appended_messages.sole[:message]).html_part.decoded, "On Tue, Sep 29, 2026 at 10:23 AM, Reports Bot"
    end

    test "mail that couldn't be sent is a draft on the server with its quote in the sender's time zone" do
      users(:one).update!(timezone: "Amsterdam")
      original = mails_messages(:inbox_read)
      original.update!(sent_at: Time.utc(2026, 9, 29, 8, 23))
      server = FakeImapServer.new(folders: [ "INBOX", "Drafts" ])
      smtp = SmtpTestHelper::FakeSmtp.new
      smtp.define_singleton_method(:start) { |*| raise SocketError, "getaddrinfo: Temporary failure in name resolution" }
      SmtpSendService.singleton_class.define_method(:new) { |*args| super(*args).tap { |service| service.define_singleton_method(:build_smtp) { smtp } } }

      connect_to_imap(server) do
        perform_enqueued_jobs(only: [ SendMailJob, SyncDraftJob ]) do
          post tool_mails_path(@tool), params: { to: "reports@example.com", subject: "Re: Lunch", body: "<p>Sure</p>", in_reply_to: original.message_id, quoted_message_id: original.id }
        end
      end

      assert_includes Mail.new(server.appended_messages.sole[:message]).html_part.decoded, "On Tue, Sep 29, 2026 at 10:23 AM, Reports Bot"
    ensure
      SmtpSendService.singleton_class.remove_method(:new)
    end

    test "a draft keeps the mail it quotes, and without it goes out without a quote" do
      original = mails_messages(:inbox_read)

      post tool_mail_drafts_path(@tool), params: { to: "reports@example.com", subject: "Re: Lunch", body: "<p>Sure</p>", in_reply_to: original.message_id, quoted_message_id: original.id }
      draft = @account.messages.drafts.find_by!(subject: "Re: Lunch")
      assert_equal original, draft.quoted_message

      get new_tool_mail_path(@tool, draft_id: draft.id)
      assert_select "input[type=hidden][name=quoted_message_id][value=?]", original.id.to_s

      patch tool_mail_draft_path(@tool, draft), params: { quoted_message_id: "" }
      assert_nil draft.reload.quoted_message
      assert_equal "<p>Sure</p>", draft.outgoing_html
    end

    test "mail sent off has left Drafts and opens as sent mail, marked until it has gone out in the background" do
      draft = mails_messages(:draft_message)
      draft.update!(uid: 9)

      post tool_mails_path(@tool), params: { draft_id: draft.id, folder: "drafts", to: "friend@example.com", bcc: "me@example.com", subject: "Plans", body: "<p>Hi</p>" }

      assert_redirected_to tool_mail_path(@tool, draft, folder: "drafts")
      assert_enqueued_with(job: SendMailJob, args: [ draft, users(:one) ])
      assert_enqueued_with(job: ImapSyncJob, args: [ @account.id, "delete_draft", 9, "Drafts" ])
      assert_equal [ [ "friend@example.com" ], [ "me@example.com" ], "Plans" ], [ draft.reload.to_addresses_list, draft.bcc_addresses_list, draft.subject ]
      assert_equal [ "Sent", false, true, nil ], draft.values_at(:folder, :draft, :sending, :uid)

      follow_redirect!
      assert_select "h1", "Plans"
      assert_select "[data-controller~='mail-sending'] .badge", text: "Sending…"
      assert_select "#conversation-#{draft.id}", count: 0
      assert_select ".mail-draft-note", count: 0

      deliveries = capture_smtp_deliveries { perform_enqueued_jobs(only: SendMailJob) }

      assert_equal [ "friend@example.com", "me@example.com" ], deliveries.sole[:recipients]
      assert_equal [ "Sent", false, false ], draft.reload.values_at(:folder, :draft, :sending)
      assert_equal draft.message_id, Mail.new(deliveries.sole[:message]).message_id
      assert_equal draft, @account.messages.sent.find_by!(subject: "Plans")

      get tool_mail_path(@tool, draft, folder: "drafts")
      assert_select "[data-controller~='mail-sending']", count: 0
    end

    test "a reply sent off shows in the conversation it answers, opened as the folder's list opens it" do
      original = mails_messages(:inbox_read)

      post tool_mails_path(@tool), params: {
        folder: "inbox", to: "reports@example.com", subject: "Re: Your weekly report", body: "<p>Thanks for these</p>", in_reply_to: original.message_id
      }

      # On the mail in the inbox, so archiving the conversation leaves the reply in Sent
      assert_redirected_to tool_mail_path(@tool, original, folder: "inbox")
      follow_redirect!
      assert_select "#conversation-#{original.id}.selected"
      assert_select "h1", "Your weekly report"
      assert_select "[data-controller~='mail-sending']", count: 1
      assert_includes response.body, "Thanks for these"

      post tool_mail_archive_path(@tool, original, folder: "inbox")
      reply = @account.messages.sent.find_by!(subject: "Re: Your weekly report")
      assert_equal [ true, false ], [ original.reload.archived?, reply.archived? ]
    end

    test "a reply to mail of your own goes to the people it went to" do
      sent = mails_messages(:sent_message)
      sent.update!(to_addresses: [ "ann@example.com" ].to_json, cc_addresses: [ "bob@example.com", @account.email_address ].to_json)

      get new_tool_mail_path(@tool, reply_to: sent.id)
      assert_select "input[name=to][value=?]", "ann@example.com"
      assert_select "input[name=cc][value=?]", ""

      get new_tool_mail_path(@tool, reply_to: sent.id, reply_all: true)
      assert_select "input[name=to][value=?]", "ann@example.com"
      assert_select "input[name=cc][value=?]", "bob@example.com"
    end

    test "a reply to all leaves out what was saved as an address of a group's name" do
      original = mails_messages(:inbox_read)
      original.update!(to_addresses: [ "undisclosed-recipients@", "@" ].to_json, cc_addresses: [ "bob@example.com" ].to_json)

      get new_tool_mail_path(@tool, reply_to: original.id, reply_all: true)

      assert_select "input[name=to][value=?]", "reports@example.com"
      assert_select "input[name=cc][value=?]", "bob@example.com"
    end

    test "mail that can't be sent stays a draft, with its attachments, and the sender hears why" do
      attachment = attachment_on(mails_messages(:inbox_read), "report.pdf")
      SmtpSendService.alias_method :send_email_without_failure, :send_email
      SmtpSendService.define_method(:send_email) { |**| raise SmtpSendService::SendError, "Error: certificate verify failed" }

      perform_enqueued_jobs(only: SendMailJob) do
        post tool_mails_path(@tool), params: {
          to: "friend@example.com", subject: "Plans", body: "<p>Hi</p>", forward_attachment_ids: [ attachment.id ],
          attachments: [ fixture_file_upload("sample.png", "image/png") ]
        }
      end

      draft = @account.messages.drafts.find_by!(subject: "Plans")
      assert_equal [ "report.pdf", "sample.png" ], draft.attachments.map(&:filename).sort
      assert_enqueued_with(job: SyncDraftJob, args: [ draft.id ])

      notification = users(:one).notifications.order(:created_at).last
      assert_equal "MailNotSentNotifier", notification.event.type
      assert_equal "Couldn't send “Plans”, it's in your drafts: Error: certificate verify failed", notification.message
      assert_equal new_tool_mail_path(@tool, draft_id: draft.id), notification.url
    ensure
      SmtpSendService.alias_method :send_email, :send_email_without_failure
      SmtpSendService.remove_method :send_email_without_failure
    end

    test "a draft with forwarded attachments sends them along from the compose page" do
      draft = mails_messages(:draft_message)
      attachment = attachment_on(draft, "report.pdf")

      get new_tool_mail_path(@tool, draft_id: draft.id)

      assert_response :success
      assert_select "input[type=hidden][name='forward_attachment_ids[]'][value=?]", attachment.id.to_s
      assert_select ".compose-attachment-item", text: /report\.pdf/
    end

    private

    def attachment_on(message, filename)
      message.attachments.create!(filename: filename, content_type: "application/pdf", file_size: 6).tap do |attachment|
        attachment.file.attach(io: StringIO.new("%PDF-1"), filename: filename, content_type: "application/pdf")
      end
    end

    # The compose page sends mail with SendMailJob
    def capture_smtp_deliveries_in_the_background(&block)
      capture_smtp_deliveries { perform_enqueued_jobs(only: SendMailJob, &block) }
    end

    # Records what would have been sent instead of talking to an SMTP server.
    def capture_sent_mail
      deliveries = []
      SmtpSendService.alias_method :send_email_without_capture, :send_email
      SmtpSendService.define_method(:send_email) { |**options| deliveries << options }
      perform_enqueued_jobs(only: SendMailJob) { yield }
      deliveries
    ensure
      SmtpSendService.alias_method :send_email, :send_email_without_capture
      SmtpSendService.remove_method :send_email_without_capture
    end
  end
end

# frozen_string_literal: true

require "application_system_test_case"

class MailsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    sign_in_as(@user)
  end

  teardown do
    FileUtils.rm_rf(@files) if @files
  end

  test "viewing inbox shows messages" do
    visit tool_mails_path(@tool)

    assert_text "Welcome to Dobase"
    assert_text "Friendly Sender"
    assert_text "Your weekly report"
    assert_text "Reports Bot"
    assert_text "Important info"
    assert_text "The Boss"

    # Trashed and archived messages should not appear in inbox
    assert_no_text "Old spam"
    assert_no_text "Archived conversation"
  end

  test "selecting a message shows detail" do
    visit tool_mails_path(@tool)

    find(".mail-list-item", text: "Welcome to Dobase").click

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5
  end

  test "in a narrow window an open conversation has the next and the previous one a button away, and the message has the width" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit tool_mails_path(@tool)
    subjects = all(".mail-list-item .mail-list-subject", minimum: 2).map(&:text)
    first(".mail-list-item a").click
    assert_selector ".mail-detail-header h1", text: subjects.first

    find("button[title^='Next conversation']").click
    assert_selector ".mail-detail-header h1", text: subjects.second
    find("button[title^='Previous conversation']").click
    assert_selector ".mail-detail-header h1", text: subjects.first
    # At the first one there is none before it: it stays
    find("button[title^='Previous conversation']").click
    assert_selector ".mail-detail-header h1", text: subjects.first

    # The message isn't set in beside the sender's face: it starts near the edge of the window
    left = page.evaluate_script("document.querySelector('.email-frame, [data-collapse-target=content] > div').getBoundingClientRect().left")
    assert_operator left, :<, 24
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a page that fills a home screen app is put back when something scrolled it" do
    visit tool_mails_path(@tool)
    wait_for_stimulus "standalone-scroll"
    # As in an installed app on a phone: the page itself never scrolls, and is a little higher than the screen
    # (scrolled and looked at in one go: it is put back a moment later)
    scrolled = page.evaluate_script(<<~JS)
      (() => {
        document.documentElement.style.overflow = "hidden"
        document.body.style.minHeight = "calc(100vh + 60px)"
        window.scrollTo(0, 60)
        return window.scrollY
      })()
    JS
    assert_operator scrolled, :>, 0

    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "the page stayed scrolled" unless page.evaluate_script("window.scrollY").zero?
    end
  end

  test "navigating to starred folder" do
    visit tool_mails_path(@tool)
    wait_for_turbo

    find("button[popovertarget='mail-folder-menu']").click

    within "#mail-folder-menu" do
      click_on "Starred"
    end

    assert_text "Important info"
    assert_text "The Boss"

    # Non-starred messages should not appear
    assert_no_text "Welcome to Dobase"
    assert_no_text "Your weekly report"
  end

  test "wide screens list the folders beside the messages" do
    page.driver.browser.manage.window.resize_to(1600, 1000)
    visit tool_mails_path(@tool)
    wait_for_turbo

    assert_no_selector "button[popovertarget='mail-folder-menu']"

    within "nav[aria-label='Mail folders']" do
      assert_link "Receipts"
      click_on "Starred"
      assert_selector "a[aria-current='page']", text: "Starred"
    end

    assert_text "Important info"
    assert_no_text "Welcome to Dobase"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "starring a message from detail view" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5

    click_with_retry("[title='Star (s)']") { message.reload.starred? }
  end

  test "starring an HTML email keeps its body visible" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_selector("iframe[data-email-frame-target=frame]") { |frame| frame.evaluate_script("this.offsetHeight") > 0 }
    click_with_retry("[title='Star (s)']") { message.reload.starred? }

    assert_selector "[title='Star (s)'] .fill-warning"
    assert_selector("iframe[data-email-frame-target=frame]") { |frame| frame.evaluate_script("this.offsetHeight") > 0 }
  end

  test "archiving a message" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5

    click_with_retry("[title='Archive (e)']") { message.reload.archived? }
  end

  test "unarchiving a message from the archive" do
    message = mails_messages(:archived_message)
    visit tool_mail_path(@tool, message, folder: "archive")
    assert_text "This has been archived.", wait: 5

    click_with_retry("[title='Unarchive (e)']") { !message.reload.archived? }

    assert_selector ".flash-toast .flash", text: "Email unarchived."
    assert_no_selector ".mail-list-item", text: "Archived conversation"
  end

  test "trashing a message" do
    message = mails_messages(:inbox_unread)
    visit tool_mail_path(@tool, message)

    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5

    click_with_retry("[title='Delete (#)']") { message.reload.trashed? }
  end

  test "the # shortcut trashes the open message" do
    message = mails_messages(:inbox_unread)
    open_message(message)

    connect_to_imap(FakeImapServer.new) do
      # Typed with Shift, the way a US keyboard does it
      find("body").send_keys("#")
      assert_db_change(-> { message.reload.trashed? })
    end
  end

  test "the u shortcut marks the open message unread and closes it" do
    message = mails_messages(:inbox_unread)
    open_message(message, folder: "inbox")
    wait_for_stimulus "hotkey", "[data-controller~='hotkey'][title^='Mark unread']"

    find("body").send_keys("u")

    assert_no_selector ".mail-detail-header"
    assert_selector ".mail-list-item span.font-semibold", text: "Friendly Sender"
    assert_not message.reload.read?
  end

  test "the # shortcut in the trash deletes the message for good, after asking" do
    message = mails_messages(:trashed_message)
    open_message(message, folder: "trash")

    connect_to_imap(FakeImapServer.new) do
      find("body").send_keys("#")
      within("dialog#turbo-confirm-dialog[open]") do
        assert_text "Permanently delete this email?"
        click_on "Delete forever"
      end
      assert_db_change(-> { !Mails::Message.exists?(message.id) })
    end
  end

  test "Trash in the command palette trashes the open message" do
    message = mails_messages(:inbox_unread)
    open_message(message)
    wait_for_stimulus "keyboard-shortcuts"
    wait_for_stimulus "command-palette"

    connect_to_imap(FakeImapServer.new) do
      find(".sidebar-jump-pill").click
      within("dialog[data-controller='command-palette']") { find("button", text: "Trash").click }
      assert_db_change(-> { message.reload.trashed? })
    end
  end

  test "accepting a calendar invite into a calendar from another calendar tool" do
    team_tool = Tool.create!(name: "Team Calendar", tool_type: tool_types(:calendar), owner: @user)
    launches = Calendars::Account.create!(tool: team_tool, provider: "local").calendars.create!(name: "Launches", remote_id: "local-launches")
    message = mails_messages(:starred_message)
    starts_at = 1.week.from_now.change(hour: 14)
    invite = message.calendar_invites.create!(uid: "tasting@example.com", method: "REQUEST", summary: "Tasting session",
                                              starts_at: starts_at, ends_at: starts_at + 1.hour)

    visit tool_mail_path(@tool, message)
    select "Team Calendar - Launches", from: "Add to calendar"
    click_on "Add to Calendar"

    assert_text "Invite accepted and added to calendar."
    assert_equal launches, invite.reload.added_to_calendar

    click_on "View in Calendar"
    assert_current_path tool_calendar_path(team_tool, week_start: starts_at.to_date)
    assert_text "Tasting session"
  end

  test "sending to a contact picked from the suggestions" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    deliveries = capture_smtp_deliveries do
      find("input[data-compose-target='to']").set("Friendly")
      find("[role=option][data-address='sender@example.com']").click
      assert_selector "#{recipients_of("to")} li", text: "Friendly Sender"
      assert_equal "Friendly Sender <sender@example.com>", find("input[name='to']", visible: :hidden).value

      find("input[name='subject']").set("Hello")
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    assert_equal [ "sender@example.com" ], deliveries.sole[:recipients]
  end

  test "a pasted list of people becomes a token each, and what is no address is marked" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    paste_into "to", "Ann Lee <ann@example.com>, joe@example.com; \"Kim, Lou\" <kim@example.com>\nnobody"

    assert_equal [ "ann@example.com", "joe@example.com", "kim@example.com", "nobody" ], addresses_in("to")
    assert_selector "li[data-address='ann@example.com']:not([data-invalid]) button[title='ann@example.com']", text: "Ann Lee"
    assert_selector "li[data-address='kim@example.com']", text: "Kim, Lou"
    assert_selector "li[data-address='nobody'][data-invalid]", text: "not a valid address"
    assert_equal 'Ann Lee <ann@example.com>, joe@example.com, "Kim, Lou" <kim@example.com>, nobody', find("input[name='to']", visible: :hidden).value
    assert_selector "#{recipients_of("to")} [role=status]", text: "4 addresses added to To", visible: :all

    # The same person twice is once
    paste_into "to", "JOE@example.com"
    assert_equal 4, addresses_in("to").size
  end

  test "a comma, a semicolon and Tab each end an address" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    input = find("input[data-compose-target='to']")
    input.send_keys("ann@example.com,", "joe@example.com;", "kim@example.com", :tab)

    assert_equal [ "ann@example.com", "joe@example.com", "kim@example.com" ], addresses_in("to")
    assert_equal "", input.value
    # Tab went on from the field
    assert_equal "Cc", evaluate_script("document.activeElement.textContent.trim()")
  end

  test "the keyboard picks from the list of people, the most written to first" do
    account = @tool.mail_account
    account.record_contact("frida@example.com", "Frida Olsen")
    3.times { account.record_contact("fritz@example.com", "Fritz Hahn") }
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    input = find("input[data-compose-target='to']")
    input.send_keys("fri")
    assert_selector "[role=option]", count: 3
    assert_equal [ "fritz@example.com", "frida@example.com", "sender@example.com" ], all("[role=option]").map { |option| option["data-address"] }
    assert_equal "true", input["aria-expanded"]
    assert_selector "[role=option][aria-selected=true]", text: "Fritz Hahn"
    assert_equal find("[role=option][aria-selected=true]")["id"], input["aria-activedescendant"]

    input.send_keys(:down, :enter)
    assert_equal [ "frida@example.com" ], addresses_in("to")
    assert_no_selector "[role=option]"
    assert_equal "false", input["aria-expanded"]
    assert_selector "#{recipients_of("to")} [role=status]", text: "Frida Olsen added to To", visible: :all

    # Who is in the field already isn't offered again; Escape shuts the list and keeps the field
    input.send_keys("fri")
    assert_selector "[role=option]", count: 2
    input.send_keys(:escape)
    assert_no_selector "[role=option]"
    assert_equal "fri", input.value
    assert_equal "compose_to", evaluate_script("document.activeElement.id")
  end

  test "a whole address that was typed is taken as it is, whoever the list offers" do
    @tool.mail_account.record_contact("ann@example.com.au", "Ann Abroad")
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    input = find("input[data-compose-target='to']")
    input.send_keys("ann@example.com")
    assert_selector "[role=option]", text: "Ann Abroad"
    assert_no_selector "[role=option][aria-selected=true]"
    input.send_keys(:enter)

    assert_equal [ "ann@example.com" ], addresses_in("to")
  end

  test "Backspace goes onto the last token and then takes it away, the arrows go along the tokens" do
    visit new_tool_mail_path(@tool, to: "ann@example.com, joe@example.com, kim@example.com")
    wait_for_stimulus "recipients"

    input = find("input[data-compose-target='to']")
    input.send_keys(:backspace)
    assert_equal "kim@example.com", token_with_keyboard
    assert_equal 3, addresses_in("to").size

    send_keys(:backspace)
    assert_equal [ "ann@example.com", "joe@example.com" ], addresses_in("to")
    assert_equal "joe@example.com", token_with_keyboard

    send_keys(:left)
    assert_equal "ann@example.com", token_with_keyboard
    send_keys(:right, :right)
    assert_equal "compose_to", evaluate_script("document.activeElement.id")
    assert_equal "ann@example.com, joe@example.com", find("input[name='to']", visible: :hidden).value
  end

  test "Shift and the arrows move a token along its field and to the field below" do
    visit new_tool_mail_path(@tool, to: "ann@example.com, joe@example.com, kim@example.com")
    wait_for_stimulus "recipients"

    find("input[data-compose-target='to']").send_keys(:backspace)
    send_keys([ :shift, :left ])
    assert_equal [ "ann@example.com", "kim@example.com", "joe@example.com" ], addresses_in("to")
    assert_equal "kim@example.com", token_with_keyboard
    assert_selector "#{recipients_of("to")} [role=status]", text: "kim@example.com, 2 of 3 in To", visible: :all

    assert_no_selector recipients_of("cc")
    send_keys([ :shift, :down ])
    assert_equal [ "ann@example.com", "joe@example.com" ], addresses_in("to")
    assert_equal [ "kim@example.com" ], addresses_in("cc")
    assert_equal "kim@example.com", token_with_keyboard
    assert_equal "kim@example.com", find("input[name='cc']", visible: :hidden).value
    assert_selector "#{recipients_of("cc")} [role=status]", text: "kim@example.com moved to Cc", visible: :all

    send_keys([ :shift, :down ], [ :shift, :up ], [ :shift, :up ])
    assert_equal [ "ann@example.com", "joe@example.com", "kim@example.com" ], addresses_in("to")
    assert_empty addresses_in("bcc")
  end

  test "a token's menu shows its address and moves it, changes it or takes it away" do
    @tool.mail_account.record_contact("ann@example.com", "Ann Lee")
    visit new_tool_mail_path(@tool, to: "ann@example.com, joe@example.com, kim@example.com")
    wait_for_stimulus "recipients"

    token("ann@example.com").click
    within("#{recipients_of("to")} [popover]") do
      assert_text "Ann Lee <ann@example.com>"
      assert_no_button "Move to To"
      click_on "Move to Bcc"
    end
    assert_equal [ "ann@example.com" ], addresses_in("bcc")
    assert_equal "Ann Lee <ann@example.com>", find("input[name='bcc']", visible: :hidden).value
    assert_equal "joe@example.com, kim@example.com", find("input[name='to']", visible: :hidden).value

    # In its new field it opens that field's menu
    token("ann@example.com").click
    within("#{recipients_of("bcc")} [popover]") { click_on "Move to To" }
    assert_equal [ "joe@example.com", "kim@example.com", "ann@example.com" ], addresses_in("to")

    token("joe@example.com").click
    within("#{recipients_of("to")} [popover]") { click_on "Remove" }
    assert_equal [ "kim@example.com", "ann@example.com" ], addresses_in("to")

    token("kim@example.com").click
    within("#{recipients_of("to")} [popover]") { click_on "Edit address" }
    input = find("input[data-compose-target='to']")
    assert_equal "kim@example.com", input.value
    input.send_keys(:backspace, :backspace, :backspace, "org", :enter)
    assert_equal [ "ann@example.com", "kim@example.org" ], addresses_in("to")
  end

  test "a token is dragged to another place in its field and to another field" do
    visit new_tool_mail_path(@tool, to: "ann@example.com, joe@example.com, kim@example.com")
    wait_for_stimulus "recipients"

    hold_token "kim@example.com"
    drop_on token("ann@example.com")
    assert_equal [ "kim@example.com", "ann@example.com", "joe@example.com" ], addresses_in("to")
    assert_equal "kim@example.com, ann@example.com, joe@example.com", find("input[name='to']", visible: :hidden).value

    # Cc waits behind its button until a token is in the hand
    assert_no_selector recipients_of("cc")
    hold_token "joe@example.com"
    assert_selector recipients_of("cc")
    assert_selector recipients_of("bcc")
    drop_on find("#{recipients_of("cc")} ul")

    assert_equal [ "joe@example.com" ], addresses_in("cc")
    assert_equal [ "kim@example.com", "ann@example.com" ], addresses_in("to")
    assert_equal "joe@example.com", find("input[name='cc']", visible: :hidden).value
    # The field it was dropped in stays; the other one is behind its button again
    assert_selector recipients_of("cc")
    assert_no_selector recipients_of("bcc")
    assert_no_selector "#{recipients_of("cc")} [popover]:popover-open"
  end

  test "an address typed and sent at once goes out with the mail" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    deliveries = capture_smtp_deliveries do
      add_recipient "friend@example.com"
      find("input[name='subject']").set("Hello")
      find("input[data-compose-target='to']").set("ann@example.com")
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    assert_equal [ "friend@example.com", "ann@example.com" ], deliveries.sole[:recipients]
  end

  test "an address typed and saved at once is in the draft" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "recipients"

    find("input[name='subject']").set("Plans")
    find("input[data-compose-target='to']").set("ann@example.com")
    click_on "Save Draft"

    assert_text "Draft saved."
    assert_equal [ "ann@example.com" ], @tool.mail_account.messages.drafts.find_by!(subject: "Plans").to_addresses_list
  end

  test "coming back to a message being written shows each recipient once" do
    visit new_tool_mail_path(@tool, to: "friend@example.com, ann@example.com")
    wait_for_stimulus "recipients"
    wait_for_turbo
    assert_selector "#{recipients_of("to")} li[data-address]", count: 2

    click_on "Project Board"
    assert_current_path tool_board_path(tools(:project_board)), wait: 10
    page.go_back

    assert_selector "#{recipients_of("to")} li[data-address]", text: "friend@example.com"
    assert_selector "#{recipients_of("to")} li[data-address]", count: 2
    assert_equal "friend@example.com, ann@example.com", find("input[name='to']", visible: :hidden).value
  end

  test "a reply sent off shows in its conversation as being sent, until it has gone out" do
    original = mails_messages(:inbox_read)
    visit new_tool_mail_path(@tool, reply_to: original.id, folder: "inbox")
    wait_for_compose_editor
    find("rhino-editor [contenteditable]").send_keys("Thanks for these")

    click_on "Send"

    assert_selector ".mail-list-item.selected", text: "Your weekly report"
    assert_selector ".mail-detail-header h1", text: "Your weekly report"
    assert_selector "[data-controller~='mail-sending']", text: "Sending…"
    within_frame(find(".mail-message-in iframe")) { assert_text "Thanks for these" }

    deliveries = capture_smtp_deliveries { perform_enqueued_jobs(only: SendMailJob) }

    assert_equal [ original.from_address ], deliveries.sole[:recipients]
    assert_no_selector "[data-controller~='mail-sending']", wait: 10
    within_frame(find(".mail-message-in iframe")) { assert_text "Thanks for these" }
  end

  test "a toast sits above the reply bar of an open mail, not over it" do
    visit tool_mail_path(@tool, mails_messages(:inbox_unread), folder: "inbox")
    find("a[title='Archive (e)']").click

    assert_selector ".flash-toast .flash", text: "Email archived."
    assert_selector ".mail-reply-bar"
    toast_bottom, bar_top = evaluate_script(<<~JS)
      [document.querySelector(".flash-toast").getBoundingClientRect().bottom, document.querySelector(".mail-reply-bar").getBoundingClientRect().top]
    JS
    assert_operator toast_bottom, :<=, bar_top
  end

  test "a reply shows the mail it quotes below the editor, and goes out without it once it's removed" do
    original = mails_messages(:inbox_read)
    original.update!(body_html: "<p>Lunch on Friday?</p>")
    visit new_tool_mail_path(@tool, reply_to: original.id)
    wait_for_compose_editor

    assert_no_text "Lunch on Friday?"
    find(".compose-quote-toggle").click
    within_frame(find(".compose-quote iframe")) do
      assert_text "wrote:"
      assert_text "Lunch on Friday?"
    end

    click_on "Remove quote"
    assert_no_selector ".compose-quote"
    deliveries = capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    assert_no_match "Lunch on Friday?", deliveries.sole[:message]
  end

  test "a part taken out of the quote of a reply doesn't go out with it" do
    original = mails_messages(:inbox_read)
    original.update!(body_html: "<p>Lunch on Friday?</p><p>The door code is 4711</p><table><tr><td>Ann</td></tr></table>")
    visit new_tool_mail_path(@tool, reply_to: original.id, folder: "inbox")
    wait_for_compose_editor
    find("rhino-editor [contenteditable]").send_keys("Yes, see you there")

    find(".compose-quote-toggle").click
    take_out_of_quote "The door code is 4711"
    type_in_quote " [code removed]"

    deliveries = capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    sent = Mail.new(deliveries.sole[:message])
    assert_no_match "4711", deliveries.sole[:message]
    assert_no_match "4711", @tool.mail_account.messages.sent.find_by!(subject: "Re: Your weekly report").body_html
    # The rest is there as it was written, layout and all, with what was typed into it
    assert_match %r{Yes, see you there</p><p[^>]*>On .* wrote:</p><blockquote[^>]*><p[^>]*>Lunch on Friday\?</p>.*\[code removed\].*<table><tbody><tr><td>Ann</td></tr></tbody></table></blockquote>}m,
      sent.html_part.decoded
    assert_match "> Lunch on Friday?", sent.text_part.decoded
  end

  test "a quote that was changed stays changed in a saved draft, and a refresh asks before it draws the form again" do
    original = mails_messages(:inbox_read)
    original.update!(body_html: "<p>Lunch on Friday?</p><p>The door code is 4711</p>")
    visit new_tool_mail_path(@tool, reply_to: original.id)
    wait_for_compose_editor

    find(".compose-quote-toggle").click
    take_out_of_quote "The door code is 4711"
    # A refresh would draw the form again as it was: with only the quote changed, it asks first
    dismiss_confirm("You have an unsent message. Discard it?") { page.execute_script("Turbo.session.refresh(location.href)") }
    within_frame(find("details.compose-quote[open] iframe")) do
      assert_text "Lunch on Friday?"
      assert_no_text "4711"
    end

    click_on "Save Draft"
    assert_text "Draft saved."
    draft = @tool.mail_account.messages.drafts.find_by!(subject: "Re: Your weekly report")
    assert_match "Lunch on Friday?", draft.quote_html
    assert_no_match "4711", draft.outgoing_html

    # The draft opens with the quote as it was left, in sight, and goes out so
    wait_for_compose_editor
    within_frame(find("details.compose-quote[open] iframe")) do
      assert_text "Lunch on Friday?"
      assert_no_text "4711"
    end
    deliveries = capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    assert_match "Lunch on Friday?", deliveries.sole[:message]
    assert_no_match "4711", deliveries.sole[:message]
  end

  test "a quote with everything taken out of it is no quote, and leaving a changed quote asks first" do
    original = mails_messages(:inbox_read)
    original.update!(body_html: "<p>Lunch on Friday?</p>")
    visit new_tool_mail_path(@tool, reply_to: original.id)
    wait_for_compose_editor

    find(".compose-quote-toggle").click
    within_frame(find(".compose-quote iframe")) { find("p", text: "Lunch on Friday?").click }
    page.execute_script("document.querySelector('.compose-quote iframe').contentDocument.execCommand('selectAll')")
    page.driver.browser.action.send_keys(:backspace).perform
    within_frame(find(".compose-quote iframe")) { assert_no_text "wrote:" }
    wait_for_turbo

    dismiss_confirm("You have an unsent message. Discard it?") { click_on "Project Board" }

    deliveries = capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    assert_no_match(/Lunch on Friday|wrote:|blockquote/, deliveries.sole[:message])
  end

  test "attachments go out with the email, however many times files are picked" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor

    deliveries = capture_smtp_deliveries do
      add_recipient "friend@example.com"
      find("input[name='subject']").set("Numbers")
      assert_field "subject", with: "Numbers"
      attach_file "attachments[]", text_file("report.txt", "numbers"), make_visible: true
      attach_file "attachments[]", text_file("notes.txt", "more numbers"), make_visible: true
      assert_text "report.txt"
      assert_text "notes.txt"

      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end

    assert_match "report.txt", deliveries.sole[:message]
    assert_match "notes.txt", deliveries.sole[:message]
    sent = @tool.mail_account.messages.sent.find_by!(subject: "Numbers")
    assert_equal [ "notes.txt", "report.txt" ], sent.attachments.pluck(:filename).sort
  end

  test "picked files are listed by name, as text, with their size" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor

    attach_file "attachments[]", text_file("<em>notes.txt", "a" * 1536), make_visible: true

    within("[data-compose-target='attachmentsList']") do
      assert_text "<em>notes.txt"
      assert_text "1.5 KB"
      assert_no_selector "em"
    end
  end

  test "saving a draft, and saving it again" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "compose"

    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")
    click_on "Save Draft"
    assert_text "Draft saved."
    draft = @tool.mail_account.messages.drafts.find_by!(subject: "Plans")
    assert_equal [ "friend@example.com" ], draft.to_addresses_list

    wait_for_stimulus "compose"
    find("input[name='subject']").set("Plans for Friday")
    click_on "Save Draft"
    assert_db_change(-> { draft.reload.subject == "Plans for Friday" })
  end

  test "leaving a reply or forward only asks to discard it once it has been changed" do
    message = mails_messages(:inbox_read)
    visit new_tool_mail_path(@tool, reply_to: message.id)
    wait_for_compose_editor
    wait_for_turbo

    click_on "Project Board"
    # The sidebar links to the tool, which redirects on to its board
    assert_current_path tool_board_path(tools(:project_board)), wait: 10

    visit new_tool_mail_path(@tool, forward: message.id)
    wait_for_compose_editor
    find("rhino-editor [contenteditable]").send_keys("FYI")
    assert_selector "rhino-editor [contenteditable]", text: "FYI"
    wait_for_turbo

    dismiss_confirm("You have an unsent message. Discard it?") { click_on "Project Board" }
    assert_current_path new_tool_mail_path(@tool, forward: message.id)
  end

  test "writing a message keeps the folder next to it, and picking a conversation asks to discard the message" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor
    assert_selector ".mail-list-item", text: "Welcome to Dobase"

    find("rhino-editor [contenteditable]").send_keys("Hello")
    assert_selector "rhino-editor [contenteditable]", text: "Hello"
    wait_for_turbo

    dismiss_confirm("You have an unsent message. Discard it?") { find(".mail-list-item", text: "Welcome to Dobase").click }
    assert_selector "rhino-editor [contenteditable]", text: "Hello"

    accept_confirm("You have an unsent message. Discard it?") { find(".mail-list-item", text: "Welcome to Dobase").click }
    assert_text "Welcome to Dobase! We hope you enjoy the platform.", wait: 5
    assert_no_selector "rhino-editor"
  end

  test "cc and bcc open from the to field" do
    visit new_tool_mail_path(@tool)
    wait_for_stimulus "compose"
    assert_no_field "compose_cc"

    click_on "Cc"
    assert_field "compose_cc", focused: true
    assert_no_button "Cc"
    assert_no_field "compose_bcc"

    click_on "Bcc"
    assert_field "compose_bcc", focused: true
  end

  test "a draft opens in the editor with space between its paragraphs and lists" do
    draft = mails_messages(:draft_message)
    draft.update!(body_html: "<p>First</p><p>Second</p><ul><li>Item</li></ul><p>Last</p>")

    visit new_tool_mail_path(@tool, draft_id: draft.id)
    wait_for_compose_editor

    gaps = evaluate_script(<<~JS)
      [...document.querySelectorAll("rhino-editor .trix-content > *")].map((block, index, blocks) =>
        index == 0 ? 0 : Math.round(block.getBoundingClientRect().top - blocks[index - 1].getBoundingClientRect().bottom))
    JS
    assert_equal 4, gaps.size
    assert gaps.drop(1).all?(&:positive?), "Blocks sit right under each other: #{gaps}"
  end

  test "leaving a message that failed to send asks to discard it" do
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor
    add_recipient "not-an-address"
    click_on "Send"
    assert_text "Invalid email address: not-an-address"
    wait_for_compose_editor
    wait_for_turbo

    dismiss_confirm("You have an unsent message. Discard it?") { click_on "Project Board" }
    assert_selector "input[name='to'][value='not-an-address']", visible: :hidden
  end

  test "an email that paints its own page has no white rim around it in a theme" do
    @user.choose_theme("tokyo-night")
    message = mails_messages(:inbox_unread)
    message.update!(body_html: %(<div style="display:none">Preview</div><table width="100%" style="background-color: #1a1b26;"><tr><td style="color: #c0caf5; padding: 24px;">A mail in a dark theme</td></tr></table>))

    visit tool_mail_path(@tool, message)
    wait_for_stimulus "email-frame"
    within_frame(find("iframe[data-email-frame-target=frame]")) { assert_text "A mail in a dark theme" }

    card_color = -> { page.evaluate_script("getComputedStyle(document.querySelector('[data-email-frame-target=card]')).backgroundColor") }
    assert_equal "rgb(26, 27, 38)", card_color.call

    auto_refresh_mail
    assert @tool.mail_account.reload.syncing?
    assert_equal "rgb(26, 27, 38)", card_color.call, "a refresh put the white card back"

    # An ordinary email stays on its white card
    message.update!(body_html: "<p>Just some words</p>")
    visit tool_mail_path(@tool, message)
    wait_for_stimulus "email-frame"
    within_frame(find("iframe[data-email-frame-target=frame]")) { assert_text "Just some words" }
    assert_equal "rgb(255, 255, 255)", card_color.call
  end

  test "a draft that fails to send stays whole, and the sender hears why" do
    draft = mails_messages(:draft_message)
    draft.update!(body_html: "<p>Hello there</p>")
    SmtpSendService.alias_method :send_email_without_failure, :send_email
    SmtpSendService.define_method(:send_email) { |**| raise SmtpSendService::SendError, "Error: certificate verify failed" }

    visit new_tool_mail_path(@tool, draft_id: draft.id)
    wait_for_compose_editor
    # Refused while the page waited for it, it opens as the draft it is again
    perform_enqueued_jobs(only: SendMailJob) do
      click_on "Send"
      assert_selector "h1", text: "Edit Draft"
    end

    # The job says why a moment after it puts the draft back, which is what the page shows
    # (a moment that is long on a busy machine)
    assert_db_change -> { users(:one).notifications.exists? }, timeout: 15
    assert_match "Error: certificate verify failed", users(:one).notifications.order(:created_at).last.message
    visit new_tool_mail_path(@tool, draft_id: draft.id)
    wait_for_compose_editor
    assert_selector "#{recipients_of("to")} li[data-address]", text: "recipient@example.com"
    assert_selector "rhino-editor [contenteditable]", text: "Hello there"
    assert_selector "input[name=draft_id][value='#{draft.id}']", visible: :hidden
  ensure
    SmtpSendService.alias_method :send_email, :send_email_without_failure
    SmtpSendService.remove_method :send_email_without_failure
  end

  test "bulk select and archive" do
    visit tool_mails_path(@tool)

    unread_message = mails_messages(:inbox_unread)
    read_message = mails_messages(:inbox_read)

    page.execute_script(<<~JS)
      const form = document.getElementById('bulk-form');
      const checkboxes = form.querySelectorAll('.mail-list-checkbox');
      checkboxes[0].checked = true;
      checkboxes[1].checked = true;

      const actionInput = document.createElement('input');
      actionInput.type = 'hidden';
      actionInput.name = 'action_type';
      actionInput.value = 'archive';
      form.appendChild(actionInput);
      form.submit();
    JS

    assert_text "2 email(s) archived."
    assert_no_text "Welcome to Dobase"
    assert_no_text "Your weekly report"
    assert unread_message.reload.archived?
    assert read_message.reload.archived?
  end

  test "the mail page doesn't sync when auto-refresh is disabled" do
    account = @tool.mail_account
    account.update!(auto_refresh_interval: 0)

    visit tool_mails_path(@tool)
    wait_for_stimulus "mail-refresh"
    # Disabled used to ask for a sync right away, and then nonstop
    sleep 1

    assert account.reload.synced?, "the mail page asked for a sync"
  end

  test "the mail page follows a new auto-refresh interval without reconnecting" do
    account = @tool.mail_account
    account.update!(auto_refresh_interval: 300)

    visit tool_mails_path(@tool)
    wait_for_stimulus "mail-refresh"
    # What the morph refresh after saving the settings does
    find("[data-controller~='mail-refresh']").execute_script("this.dataset.mailRefreshIntervalValue = '1'")

    assert_db_change(-> { account.reload.syncing? })
  end

  test "auto-refresh waits while conversations are ticked, a search is typed or a dialog is open" do
    account = @tool.mail_account
    visit tool_mails_path(@tool)
    wait_for_stimulus "mail-refresh"
    wait_for_stimulus "mail-bulk"

    first(".mail-list-checkbox").click
    auto_refresh_mail
    assert first(".mail-list-checkbox").checked?, "the refresh unticked the conversation"
    first(".mail-list-checkbox").click

    find("input[type=search]").send_keys("week")
    auto_refresh_mail
    assert_equal "week", find("input[type=search]").value
    find("input[type=search]").send_keys([ :backspace ] * 4)

    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{@tool.id}']", visible: :all).execute_script("this.click()")
    assert_selector "dialog#edit-tool-modal[open]"
    auto_refresh_mail
    assert_selector "dialog#edit-tool-modal[open]"
    assert account.reload.synced?, "the mail page asked for a sync"

    find("dialog#edit-tool-modal[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    execute_script("document.activeElement.blur()")
    auto_refresh_mail
    assert account.reload.syncing?, "the mail page didn't refresh once it could"
  end

  test "a refresh keeps the images the reader asked for" do
    message = mails_messages(:inbox_unread)
    message.update!(body_html: %(<p>Our logo</p><img src="https://images.example.invalid/logo.png" alt="logo">))
    visit tool_mail_path(@tool, message)
    wait_for_stimulus "email-frame"

    click_on "Show images"
    assert_no_text "Images are hidden"
    auto_refresh_mail

    assert @tool.mail_account.reload.syncing?
    assert_no_text "Images are hidden"
    assert_includes find("iframe[data-email-frame-target=frame]")["srcdoc"], %(src="https://images.example.invalid/logo.png")
  end

  test "a refresh leaves a long mail where the reader had scrolled it" do
    message = mails_messages(:inbox_unread)
    message.update!(body_html: (1..200).map { |line| "<p>Line #{line} of a long mail</p>" }.join)
    visit tool_mail_path(@tool, message)
    wait_for_stimulus "email-frame"
    within_frame(find("iframe[data-email-frame-target=frame]")) { assert_text "Line 200 of a long mail" }

    reader = find("[data-mail-keyboard-target=reader]")
    reader.execute_script("this.scrollTop = 2000")
    assert_equal 2000, reader.evaluate_script("this.scrollTop")
    auto_refresh_mail

    assert @tool.mail_account.reload.syncing?
    assert_equal 2000, reader.evaluate_script("this.scrollTop"), "the refresh scrolled the mail back up"
  end

  test "a refresh keeps an earlier message of the conversation open" do
    visit tool_mail_path(@tool, mails_messages(:sent_message))
    wait_for_stimulus "collapse"
    assert_selector "[data-collapse-target=content]", text: "Thanks for the report."
    assert_no_selector "[data-collapse-target=content]", text: "Here is your weekly report summary."

    find("button[data-action='click->collapse#toggle']", text: "Reports Bot").click
    assert_selector "[data-collapse-target=content]", text: "Here is your weekly report summary."
    auto_refresh_mail

    assert @tool.mail_account.reload.syncing?
    assert_selector "[data-collapse-target=content]", text: "Here is your weekly report summary."
    assert_selector "[data-collapse-target=content]", text: "Thanks for the report."
  end

  test "an open message says everyone it went to under its sender, a closed one in a line" do
    mails_messages(:inbox_read).update!(cc_addresses: [ "boss@example.com" ].to_json)
    visit tool_mail_path(@tool, mails_messages(:sent_message))
    wait_for_stimulus "collapse"

    # The last message is open, the one it answers closed
    assert_selector ".mail-recipients", text: /To\s+Reports Bot reports@example\.com/
    assert_selector "[data-collapse-target=preview]", text: "To: Test User · Cc: boss@example.com"
    assert_no_selector ".mail-recipients", text: "boss@example.com"

    find("button[data-action='click->collapse#toggle']", text: "Reports Bot").click
    assert_selector ".mail-recipients", text: /To\s+Test User testuser@example\.com\s+Cc\s+boss@example\.com/
    assert_no_selector "[data-collapse-target=preview]", text: "boss@example.com"

    # They are text to read and to copy, not the button: a click on one leaves the message open,
    # and they stand under the sender's name, beside the face
    find(".mail-recipient", text: "boss@example.com").click
    assert_selector ".mail-recipients", text: "boss@example.com"
    name, people = [ ".mail-message-toggle", ".mail-recipients" ].map { |part| first(part).evaluate_script("this.getBoundingClientRect().left") }
    assert_in_delta name, people, 1

    find("button[data-action='click->collapse#toggle']", text: "Reports Bot").click
    assert_no_selector ".mail-recipients", text: "boss@example.com"
    assert_selector "[data-collapse-target=preview]", text: "To: Test User · Cc: boss@example.com"
  end

  test "at a phone's width everyone an open message went to has the width, and a long address breaks" do
    long = "partnerships-and-sponsoring-europe@a-rather-long-company-name-international.example"
    mails_messages(:sent_message).update!(to_addresses: [ "reports@example.com", long, *(1..9).map { |number| "guest#{number}@example.com" } ].to_json)
    # (a window of Chrome's own goes no narrower than 500px, where the people still stand beside the face)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false)
    visit tool_mail_path(@tool, mails_messages(:sent_message))
    wait_for_stimulus "collapse"

    assert_equal 390, page.evaluate_script("window.innerWidth")
    assert_selector ".mail-recipients .mail-recipient", count: 11
    face, people, reader = [ ".mail-message-face", ".mail-recipients", "[data-mail-keyboard-target=reader]" ].map do |part|
      all(part).last.evaluate_script("(({ left, right, top, bottom }) => ({ left, right, top, bottom }))(this.getBoundingClientRect())")
    end
    assert_in_delta face["left"], people["left"], 1, "the people stand beside the face, not under it"
    assert_operator people["top"], :>=, face["bottom"] - 1
    assert_operator people["right"], :<=, reader["right"], "the people run out of the window"
    assert all(".mail-recipient").all? { |person| person.evaluate_script("this.getBoundingClientRect().right") <= people["right"] }, "an address runs out of the window"
    # The closed message keeps to one line
    assert_in_delta 16, find("[data-collapse-target=preview]").evaluate_script("this.getBoundingClientRect().height"), 2
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "mail settings that can't be saved show what to fix" do
    open_mail_settings
    within "dialog#edit-tool-modal[open]" do
      click_on "Email"
      fill_in "IMAP Server", with: "   "
      click_on "Save Changes"
    end

    assert_text "IMAP server can't be blank"
    fill_in "IMAP Server", with: "imap.fixed.example.com"
    click_on "Save Changes"

    assert_text "Mail account updated successfully."
    assert_equal "imap.fixed.example.com", @tool.mail_account.reload.imap_host
  end

  private

  # What the auto-refresh timer does when its minute is up
  def auto_refresh_mail
    page.evaluate_async_script(<<~JS)
      const element = document.querySelector("[data-controller~='mail-refresh']")
      window.Stimulus.getControllerForElementAndIdentifier(element, "mail-refresh").sync().then(arguments[0])
    JS
    wait_for_turbo
  end

  # The editor takes the prefilled body, and typing, once it has started. Headless Chrome
  # can drop input that arrives before the page has shown a frame, so wait for two.
  def wait_for_compose_editor
    wait_for_stimulus "compose"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The editor hasn't started" unless evaluate_script("document.querySelector('rhino-editor').hasInitialized")
    end
    page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
  end

  # --- The address fields ---

  def recipients_of(field)
    "[data-recipients-field-value='#{field}']"
  end

  def addresses_in(field)
    all("#{recipients_of(field)} li[data-address]").map { |token| token["data-address"] }
  end

  def token(address)
    find("li[data-address='#{address}'] button")
  end

  # The keyboard is on a token: the last one, by Backspace from the place to type
  def token_with_keyboard
    evaluate_script("document.activeElement.closest('li[data-address]')?.dataset.address")
  end

  # A drag by the mouse, in steps: the page looks where the token is every moment or so
  def hold_token(address)
    page.driver.browser.action.click_and_hold(token(address).native).move_by(0, 6).pause(duration: 0.1).move_by(0, 6).pause(duration: 0.1).perform
  end

  def drop_on(element)
    page.driver.browser.action.move_to(element.native).pause(duration: 0.2).move_by(2, 0).pause(duration: 0.2).release.perform
  end

  def paste_into(field, text)
    execute_script(<<~JS, find("#{recipients_of(field)} input[type=text]"), text)
      const clipboard = new DataTransfer()
      clipboard.setData("text/plain", arguments[1])
      arguments[0].focus()
      arguments[0].dispatchEvent(new ClipboardEvent("paste", { clipboardData: clipboard, bubbles: true, cancelable: true }))
    JS
  end

  # The paragraph of the quoted mail with this text, selected the way a pointer would and deleted
  def take_out_of_quote(text)
    within_frame(find(".compose-quote iframe")) { find("p", text: text).click }
    page.execute_script(<<~JS, text)
      const quote = document.querySelector(".compose-quote iframe").contentDocument
      const paragraph = [...quote.querySelectorAll("p")].find(paragraph => paragraph.textContent.includes(arguments[0]))
      quote.getSelection().selectAllChildren(paragraph)
    JS
    page.driver.browser.action.send_keys(:backspace).perform
    within_frame(find(".compose-quote iframe")) { assert_no_text text }
  end

  # Typed where the keyboard is in the quote
  def type_in_quote(text)
    page.driver.browser.action.send_keys(text).perform
    within_frame(find(".compose-quote iframe")) { assert_text text.strip }
  end

  def add_recipient(address)
    find("input[data-compose-target='to']").set(address).send_keys(:enter)
  end

  def text_file(name, content)
    @files ||= Dir.mktmpdir
    File.join(@files, name).tap { |path| File.write(path, content) }
  end

  def open_message(message, folder: nil)
    visit tool_mail_path(@tool, message, folder: folder)
    assert_text message.body_plain, wait: 5
    wait_for_turbo
    wait_for_stimulus "hotkey", "[data-controller~='hotkey'][title^='Delete']"
  end

  def open_mail_settings
    visit tool_mails_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sidebar"
    # The settings gear only shows on hover
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{@tool.id}']", visible: :all).execute_script("this.click()")
  end

  # Click an element and retry if the expected condition isn't met.
  # Turbo method links sometimes fail to fire in headless Chrome.
  def click_with_retry(selector, retries: 3, &condition)
    wait_for_turbo
    (retries + 1).times do |attempt|
      find(selector).click
      assert_db_change(condition, timeout: 5)
      return
    rescue RuntimeError
      raise if attempt == retries
      sleep 0.5
    end
  end
end

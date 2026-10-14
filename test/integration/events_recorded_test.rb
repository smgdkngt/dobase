# frozen_string_literal: true

require "test_helper"

# What is done in a tool is written down as an event (Event), for whoever listens
# from outside the browser: by the models, not by the controllers. Here it is done
# the way the app, the API or the CLI does it, for what a request adds (who did
# it, with which token) and for mail, whose events Mails::Account's methods write.
# What a card, a comment and a chat message write by themselves is in
# test/models/events_written_test.rb.
class EventsRecordedTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @headers = api_headers(@user, name: "Claude")
    @board = tools(:project_board)
    @card = cards(:first_task)
    @mail = tools(:my_mail)
    @account = mails_accounts(:primary)
  end

  # --- Cards ---

  test "no controller writes an event: a model does, however it is reached" do
    writing = Rails.root.glob("app/controllers/**/*.rb").select { |file| file.read.match?(/record_event|(?<![:\w])Event\.(record|create|new)/) }

    assert_empty writing.map { |file| file.relative_path_from(Rails.root).to_s }
  end

  test "a card made says who made it, and with which token" do
    events = events_of { post column_cards_path(columns(:todo)), params: { card: { title: "Harvest" } }, headers: @headers, as: :json }

    card = Boards::Card.find_by!(title: "Harvest")
    assert_equal [ [ "card.created", card.id, { "title" => "Harvest", "column" => "To Do" } ] ], summary(events)
    assert_equal [ @user.id, "Claude" ], events.sole.values_at(:user_id, :via)
  end

  test "a card that couldn't be made is no event" do
    assert_empty events_of { post column_cards_path(columns(:todo)), params: { card: { title: "" } }, headers: @headers, as: :json }
  end

  test "a card dragged to another column in the browser, not the cards that make room for it" do
    sign_in_as @user
    staying = cards(:completed_task)

    events = events_of { patch column_positions_path(columns(:done)), params: { card_ids: [ @card.id, staying.id ] }, as: :json }

    assert_equal [ [ "card.moved", @card.id, { "title" => "First task", "column" => "Done", "moved_from" => "To Do" } ] ], summary(events)
    assert_equal [ [ columns(:done).id, 0 ], [ columns(:done).id, 1 ] ], [ @card, staying ].map { |card| card.reload.values_at(:column_id, :position) }
    assert_nil events.sole.via
    assert_equal @user.id, events.sole.user_id
  end

  # --- Mail, done here ---

  test "mail archived and unarchived" do
    message = mails_messages(:inbox_read)

    events = events_of do
      post tool_mail_archive_path(@mail, message), headers: @headers, as: :json
      delete tool_mail_archive_path(@mail, message), headers: @headers, as: :json
    end

    assert_equal %w[mail.archived mail.unarchived], events.map(&:kind)
    assert_equal({ "from" => "reports@example.com", "from_name" => "Reports Bot", "subject" => "Your weekly report", "folder" => "INBOX" }, events.first.data)
  end

  test "mail moved to a folder" do
    message = mails_messages(:inbox_read)

    events = events_of { post tool_mail_move_path(@mail, message), params: { folder: "Receipts" }, headers: @headers, as: :json }

    assert_equal [ [ "mail.moved", message.id,
      { "from" => "reports@example.com", "from_name" => "Reports Bot", "subject" => "Your weekly report", "folder" => "Receipts", "moved_from" => "INBOX" } ] ], summary(events)
  end

  test "mail trashed is deleted, and restored is moved back" do
    @account.update!(synced_folders: %w[INBOX Sent Trash Receipts].to_json)
    message = mails_messages(:inbox_read)

    events = events_of do
      post tool_mail_trash_path(@mail, message), headers: @headers, as: :json
      delete tool_mail_trash_path(@mail, message), headers: @headers, as: :json
    end

    assert_equal [ [ "mail.deleted", "Trash", "INBOX" ], [ "mail.moved", "INBOX", "Trash" ] ],
      events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }
  end

  test "mail moved to junk and back is moved" do
    @account.update!(synced_folders: %w[INBOX Sent Junk].to_json)
    message = mails_messages(:inbox_read)

    events = events_of do
      post tool_mail_junk_path(@mail, message), headers: @headers, as: :json
      delete tool_mail_junk_path(@mail, message), headers: @headers, as: :json
    end

    assert_equal [ [ "mail.moved", "Junk", "INBOX" ], [ "mail.moved", "INBOX", "Junk" ] ],
      events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }
  end

  test "a draft written, saved, moved or restored is nobody's news" do
    @account.update!(synced_folders: %w[INBOX Sent Trash Receipts].to_json)
    draft = mails_messages(:draft_message)

    events = events_of do
      post tool_mail_drafts_path(@mail), params: { to: "ann@example.com", subject: "New" }, headers: @headers, as: :json
      patch tool_mail_draft_path(@mail, draft), params: { subject: "Changed" }, headers: @headers, as: :json
      post tool_mail_move_path(@mail, draft), params: { folder: "Receipts" }, headers: @headers, as: :json
    end
    assert_empty events

    post tool_mail_trash_path(@mail, draft), headers: @headers, as: :json
    assert_empty events_of { delete tool_mail_trash_path(@mail, draft), headers: @headers, as: :json }
  end

  test "a draft thrown away says what it was called and who it was for, in the trash or at once" do
    @account.update!(synced_folders: %w[INBOX Sent Trash Receipts].to_json)
    draft = mails_messages(:draft_message)

    events = events_of { post tool_mail_trash_path(@mail, draft), headers: @headers, as: :json }
    assert_equal [ [ "mail.draft_discarded", draft.id, { "subject" => "Draft email", "to" => [ "recipient@example.com" ] } ] ], summary(events)
    assert_equal [ @user.id, "Claude" ], events.sole.values_at(:user_id, :via)

    sign_in_as @user
    other = @account.new_draft(to_addresses: [ "bob@example.com" ].to_json, subject: "Never mind")
    other.save!
    events = events_of { delete tool_mail_path(@mail, other) }
    assert_equal [ [ "mail.draft_discarded", other.id, { "subject" => "Never mind", "to" => [ "bob@example.com" ] } ] ], summary(events)
    assert_not Mails::Message.exists?(other.id)
  end

  test "mail sent through the API says who it went to and which mail it answers" do
    original = mails_messages(:inbox_read)
    draft = mails_messages(:draft_message)

    events = events_of do
      capture_smtp_deliveries do
        post tool_mails_path(@mail), headers: @headers, as: :json, params: {
          to: "reports@example.com", subject: "Re: Your weekly report", body: "<p>Thanks</p>",
          in_reply_to: original.message_id, quoted_message_id: original.id, draft_id: draft.id
        }
      end
    end
    assert_response :created

    sent = @account.messages.find_by!(folder: "Sent", subject: "Re: Your weekly report")
    assert_equal [ [ "mail.sent", sent.id, { "from" => @account.email_address, "from_name" => @account.display_name, "subject" => "Re: Your weekly report",
      "folder" => "Sent", "to" => [ "reports@example.com" ], "in_reply_to" => "#{@mail.id}/#{original.id}" } ] ], summary(events)
    assert_equal [ @user.id, "Claude" ], events.sole.values_at(:user_id, :via)
  end

  test "mail sent from the compose page is said once it went out, by whoever sent it" do
    sign_in_as @user
    original = mails_messages(:inbox_read)

    capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        post tool_mails_path(@mail), params: { to: "boss@example.com", subject: "Fwd: Your weekly report", body: "<p>FYI</p>", quoted_message_id: original.id }
      end
    end

    event = Event.where(kind: "mail.sent").sole
    sent = @account.messages.find_by!(folder: "Sent", subject: "Fwd: Your weekly report")
    assert_equal [ sent.id, @user.id, nil ], event.values_at(:record_id, :user_id, :via)
    assert_equal [ [ "boss@example.com" ], "#{@mail.id}/#{original.id}", nil ], event.data.values_at("to", "forwards", "in_reply_to")
  end

  test "mail the mail server refused is not sent" do
    sign_in_as @user
    smtp = SmtpTestHelper::FakeSmtp.new
    smtp.define_singleton_method(:send_message) { |*| raise Net::SMTPFatalError, "550 No such user" }
    SmtpSendService.singleton_class.define_method(:new) { |*args| super(*args).tap { |service| service.define_singleton_method(:build_smtp) { smtp } } }

    events = events_of do
      perform_enqueued_jobs(only: SendMailJob) { post tool_mails_path(@mail), params: { to: "nobody@example.com", subject: "Hi", body: "<p>Hi</p>" } }
    end

    assert_empty events
  ensure
    SmtpSendService.singleton_class.remove_method(:new)
  end

  # --- Files and calendars ---

  test "a file uploaded says who uploaded it, and with which token" do
    events = events_of do
      post tool_files_uploads_path(tools(:my_files)), headers: @headers,
        params: { files: [ Rack::Test::UploadedFile.new(StringIO.new("1"), "text/plain", original_filename: "one.txt"),
                           Rack::Test::UploadedFile.new(StringIO.new("22"), "text/plain", original_filename: "two.txt") ] }
    end

    assert_equal [ [ "file.created", "one.txt", nil, 1 ], [ "file.created", "two.txt", nil, 2 ] ],
      events.map { |event| [ event.kind, *event.data.values_at("name", "folder", "size") ] }
    assert_equal [ [ @user.id, "Claude" ] ], events.map { |event| event.values_at(:user_id, :via) }.uniq
  end

  test "an appointment made, moved and deleted through the API" do
    calendar_tool = tools(:my_calendar)

    events = events_of do
      post tool_calendar_events_path(calendar_tool), headers: @headers, as: :json,
        params: { calendars_event: { summary: "Dentist", start_time: "2030-01-10 14:30", end_time: "2030-01-10 15:00", calendar_id: calendars_calendars(:personal).id } }
      event = Calendars::Event.find_by!(summary: "Dentist")
      patch tool_calendar_event_path(calendar_tool, event), headers: @headers, as: :json,
        params: { calendars_event: { start_time: "2030-01-10 16:00", end_time: "2030-01-10 16:30" } }
      delete tool_calendar_event_path(calendar_tool, event), headers: @headers, as: :json
    end

    assert_equal [ [ "calendar.event_created", nil ], [ "calendar.event_updated", %w[starts_at ends_at] ], [ "calendar.event_deleted", nil ] ],
      events.map { |event| [ event.kind, event.data["changed"] ] }
    assert_equal [ [ calendar_tool.id, @user.id, "Claude" ] ], events.map { |event| event.values_at(:tool_id, :user_id, :via) }.uniq
  end

  test "mail archived, moved and trashed several at once" do
    sign_in_as @user
    first, second = mails_messages(:inbox_unread), mails_messages(:inbox_read)

    events = events_of { post tool_bulk_path(@mail), params: { message_ids: [ first.id, second.id ], action_type: "archive" } }
    assert_equal [ [ "mail.archived", first.id ], [ "mail.archived", second.id ] ].sort, events.map { |event| [ event.kind, event.record_id ] }.sort

    events = events_of { post tool_bulk_path(@mail), params: { message_ids: [ mails_messages(:starred_message).id ], action_type: "move_to_folder", target_folder: "Receipts" } }
    assert_equal [ [ "mail.moved", "Receipts", "INBOX" ] ], events.map { |event| [ event.kind, event.data["folder"], event.data["moved_from"] ] }

    events = events_of { post tool_bulk_path(@mail), params: { message_ids: [ mails_messages(:starred_message).id ], action_type: "trash", folder: "Receipts" } }
    assert_equal %w[mail.deleted], events.map(&:kind)
  end

  test "mail read, starred or deleted for good from the trash is no event" do
    sign_in_as @user
    message = mails_messages(:inbox_unread)

    events = events_of do
      post tool_mail_read_path(@mail, message), as: :json
      post tool_mail_star_path(@mail, message), as: :json
      post tool_bulk_path(@mail), params: { message_ids: [ mails_messages(:trashed_message).id ], action_type: "delete", folder: "trash" }
    end

    assert_empty events
  end

  test "no event carries what a mail says" do
    message = mails_messages(:inbox_unread)
    message.update!(body_plain: "The code is 4711-secret", body_html: "<p>The code is 4711-secret</p>")
    @account.update!(synced_folders: %w[INBOX Sent Trash Receipts].to_json)

    events = events_of do
      post tool_mail_archive_path(@mail, message), headers: @headers, as: :json
      delete tool_mail_archive_path(@mail, message), headers: @headers, as: :json
      post tool_mail_move_path(@mail, message), params: { folder: "Receipts" }, headers: @headers, as: :json
      post tool_mail_trash_path(@mail, message), headers: @headers, as: :json
    end

    assert_equal 4, events.size
    events.each do |event|
      assert_equal %w[folder from from_name moved_from subject], (event.data.keys | %w[folder from from_name moved_from subject]).sort
      assert_no_match(/4711|secret/, event.data.to_json)
    end
    get events_path, params: { after: 0 }, headers: @headers
    assert_no_match(/4711|secret/, response.body)
  end

  private
    def events_of
      before = Event.maximum(:id).to_i
      yield
      Event.where(id: (before + 1)..).order(:id).to_a
    end

    def summary(events)
      events.map { |event| [ event.kind, event.record_id, event.data ] }
    end
end

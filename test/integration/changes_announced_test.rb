# frozen_string_literal: true

require "test_helper"

# Whatever changes something in a tool says so to the pages that have the tool open
# (AnnouncesChanges), so a board shows a card made from the CLI without being loaded
# again. Every action that writes inside a tool does, by itself; the ones below
# don't, each for a reason. A new action that should keep quiet fails this test until
# it is listed here.
#
# For the tools whose pages listen (ApplicationHelper::LIVE_PAGES) every way to change
# them is tried as well: an action that writes and isn't tried fails too.
class ChangesAnnouncedTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  # Something of your own that nobody else's page shows: that you have seen a tool or
  # read a chat, that it is muted for you, a download
  YOUR_OWN = %w[
    tools/visits#create
    tools/chats/reads#create
    tools/mutes#create
    tools/mutes#destroy
    tools/files/downloads#create
  ].freeze

  # Shown by the tool's own stream as it happens: a chat's messages and reactions
  # (Turbo Streams), who is in a call (the notification stream)
  SHOWN_AS_IT_HAPPENS = %w[
    tools/chats/messages#create
    tools/chats/messages#update
    tools/chats/messages#destroy
    tools/chats/messages/reactions#create
    tools/chats/messages/reactions#destroy
    tools/rooms/activities#create
    tools/rooms/activities#destroy
  ].freeze

  # Nothing in the tool changes: a pass into a call, a notification to someone named
  NOTHING_IN_THE_TOOL = %w[
    tools/rooms/tokens#create
    tools/docs/documents/mentions#create
  ].freeze

  # Starts a job, and the change is the job's to announce
  A_JOBS = %w[
    tools/mails/syncs#create
    tools/calendars/syncs#create
  ].freeze

  WRITES = %w[POST PATCH PUT DELETE].freeze

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "every action that writes inside a tool announces it, but for the ones listed" do
    quiet = writes.reject { |controller, action| controller.announces_change?(action) }
      .map { |controller, action| "#{controller.controller_path}##{action}" }
    listed = YOUR_OWN + SHOWN_AS_IT_HAPPENS + NOTHING_IN_THE_TOOL + A_JOBS

    assert_empty quiet - listed, "These keep quiet about what they change. List each in #{self.class.name} with its reason."
    assert_empty listed - quiet, "These announce what they change now (or are gone): take them off the list in #{self.class.name}."
  end

  test "every way to change a board is heard by the pages that have it open" do
    tool = tools(:project_board)
    todo, doing = columns(:todo), columns(:in_progress)
    card = cards(:first_task)
    file = -> { { file: fixture_file_upload("sample.png", "image/png") } }

    tried = [
      announced(tool) { post column_cards_path(todo), params: { card: { title: "New" } }, as: :json },
      announced(tool) { patch column_positions_path(doing), params: { card_ids: [ card.id ] }, as: :json },
      announced(tool) { patch tool_board_card_path(tool, card), params: { card: { color: "red" } }, as: :json },
      announced(tool) { patch tool_board_card_position_path(tool, card), params: { column_id: todo.id }, as: :json },
      announced(tool) { post tool_board_card_comments_path(tool, card), params: { body: "Looks good" }, as: :json },
      announced(tool) { delete tool_board_card_comment_path(tool, card, card.comments.last), as: :json },
      announced(tool) { post tool_board_card_attachments_path(tool, card), params: file.call, headers: { "Accept" => "application/json" } },
      announced(tool) { delete tool_board_card_attachment_path(tool, card, card.attachments.last), as: :json },
      announced(tool) { post tool_board_card_archive_path(tool, card), as: :json },
      announced(tool) { delete tool_board_card_archive_path(tool, card), as: :json },
      announced(tool) { delete tool_board_card_path(tool, card), as: :json },
      announced(tool) { post tool_board_columns_path(tool), params: { name: "Later" }, as: :json },
      announced(tool) { patch tool_board_column_path(tool, doing), params: { name: "Doing" }, as: :json },
      announced(tool) { patch tool_board_positions_path(tool), params: { column_ids: [ doing.id, todo.id ] }, as: :json },
      announced(tool) { delete tool_board_column_path(tool, doing), as: :json }
    ]

    assert_empty writes_of("tools/boards", "columns") - tried, "These change a board and aren't tried here"
  end

  test "every way to change a todo list is heard by the pages that have it open" do
    tool = tools(:my_todos)
    main, backlog = todo_lists(:main), todo_lists(:backlog)
    item = todo_items(:pending_one)
    file = -> { { file: fixture_file_upload("sample.png", "image/png") } }

    tried = [
      announced(tool) { post todo_list_items_path(main), params: { item: { title: "New" } }, as: :json },
      announced(tool) { patch todo_list_positions_path(backlog), params: { item_ids: [ item.id ] }, as: :json },
      announced(tool) { patch tool_todo_item_path(tool, item), params: { item: { title: "Renamed" } }, as: :json },
      announced(tool) { patch tool_todo_item_position_path(tool, item), params: { todo_list_id: main.id }, as: :json },
      announced(tool) { post tool_todo_item_completion_path(tool, item), as: :json },
      announced(tool) { delete tool_todo_item_completion_path(tool, item), as: :json },
      announced(tool) { post tool_todo_item_comments_path(tool, item), params: { body: "On it" }, as: :json },
      announced(tool) { delete tool_todo_item_comment_path(tool, item, item.comments.order(:id).last), as: :json },
      announced(tool) { post tool_todo_item_attachments_path(tool, item), params: file.call, headers: { "Accept" => "application/json" } },
      announced(tool) { delete tool_todo_item_attachment_path(tool, item, item.attachments.last), as: :json },
      announced(tool) { delete tool_todo_item_path(tool, item), as: :json },
      announced(tool) { post tool_todo_lists_path(tool), params: { title: "Later" }, as: :json },
      announced(tool) { patch tool_todo_list_path(tool, backlog), params: { title: "Someday" }, as: :json },
      announced(tool) { patch tool_todo_positions_path(tool), params: { list_ids: [ backlog.id, main.id ] }, as: :json },
      announced(tool) { delete tool_todo_list_path(tool, backlog), as: :json }
    ]

    assert_empty writes_of("tools/todos", "todo_lists") - tried, "These change a todo list and aren't tried here"
  end

  test "every way to change what is in a files tool is heard by the pages that have it open" do
    tool = tools(:my_files)
    folder, file = file_folders(:photos), file_items(:readme)
    upload = -> { { file: fixture_file_upload("sample.png", "image/png") } }

    tried = [
      announced(tool) { post tool_files_folders_path(tool), params: { name: "New" }, as: :json },
      announced(tool) { patch tool_files_folder_path(tool, folder), params: { folder: { name: "Pictures" } }, as: :json },
      announced(tool) { post tool_files_folder_share_path(tool, folder) },
      announced(tool) { delete tool_files_folder_share_path(tool, folder) },
      announced(tool) { post tool_files_uploads_path(tool), params: upload.call, headers: { "Accept" => "application/json" } },
      announced(tool) { patch tool_files_item_path(tool, file), params: { file: { name: "read-me.md" } }, as: :json },
      announced(tool) { post tool_files_item_share_path(tool, file) },
      announced(tool) { delete tool_files_item_share_path(tool, file) },
      announced(tool) { post tool_files_deletion_path(tool), params: { file_ids: [ file_items(:report).id ] } },
      announced(tool) { delete tool_files_item_path(tool, file), as: :json },
      announced(tool) { delete tool_files_folder_path(tool, folder), as: :json }
    ]

    assert_empty writes_of("tools/files") - tried, "These change what is in a files tool and aren't tried here"
  end

  test "every way to change a documents list is heard by the pages that have it open" do
    tool = tools(:my_docs)
    document = docs_documents(:meeting_notes)

    tried = [
      announced(tool) { post tool_docs_documents_path(tool), params: { docs_document: { title: "New" } }, as: :json },
      announced(tool) { patch tool_docs_document_path(tool, document), params: { docs_document: { title: "Minutes" } }, as: :json },
      announced(tool) { delete tool_docs_document_path(tool, document), as: :json }
    ]

    assert_empty writes_of("tools/docs") - tried, "These change a documents list and aren't tried here"
  end

  test "every way to change a calendar is heard by the pages that have it open" do
    tool = tools(:my_calendar)
    event = calendars_events(:meeting)
    invite = ->(summary) do
      mails_messages(:inbox_unread).calendar_invites.create!(uid: "#{SecureRandom.uuid}@example.com", summary: summary,
        starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour, status: "pending")
    end
    unconnected = Tool.create!(name: "Team Calendar", tool_type: tool_types(:calendar), owner: @user)

    tried = [
      announced(tool) { post tool_calendar_events_path(tool), params: { calendars_event: { summary: "New", start_time: "2030-01-08T14:00", end_time: "2030-01-08T15:00" } }, as: :json },
      announced(tool) { patch tool_calendar_event_path(tool, event), params: { calendars_event: { summary: "Renamed" } }, as: :json },
      announced(tool) { delete tool_calendar_event_path(tool, event), as: :json },
      announced(tool) { post tool_calendar_invites_path(tool), params: { invite_id: invite.call("Planning").id, calendar_id: calendars_calendars(:personal).id } },
      announced(tool) { delete tool_calendar_invite_path(tool, invite.call("Board meeting")) },
      announced(tool) { patch tool_calendar_account_path(tool), params: { calendars_account: { calendars_attributes: [ { id: calendars_calendars(:work).id, enabled: "0" } ] } } },
      announced(unconnected) { post tool_calendar_account_path(unconnected), params: { calendars_account: { provider: "local" } } }
    ]

    assert_empty writes_of("tools/calendars") - tried, "These change a calendar and aren't tried here"
  end

  test "every way to change a mailbox is heard by the pages that have it open" do
    tool = tools(:my_mail)
    message, draft = mails_messages(:inbox_read), mails_messages(:draft_message)
    upload = -> { { files: [ fixture_file_upload("sample.png", "image/png") ] } }
    unconnected = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: @user)
    account = { email_address: "support@example.com", username: "support@example.com", password: "secret",
      imap_host: "imap.example.com", smtp_host: "smtp.example.com" }

    tried = [
      announced(tool) { post tool_mail_read_path(tool, mails_messages(:inbox_unread)) },
      announced(tool) { delete tool_mail_read_path(tool, message) },
      announced(tool) { post tool_mail_star_path(tool, message) },
      announced(tool) { delete tool_mail_star_path(tool, message) },
      announced(tool) { post tool_mail_archive_path(tool, message) },
      announced(tool) { delete tool_mail_archive_path(tool, message) },
      announced(tool) { post tool_mail_trash_path(tool, message) },
      announced(tool) { delete tool_mail_trash_path(tool, message) },
      announced(tool) { post tool_mail_move_path(tool, message), params: { folder: "Sent" } },
      announced(tool) { post tool_mail_trusted_sender_path(tool, message) },
      announced(tool) { delete tool_mail_trusted_sender_path(tool, message) },
      announced(tool) { post tool_bulk_path(tool), params: { message_ids: [ mails_messages(:starred_message).id ], action_type: "archive" } },
      announced(tool) { post tool_mail_drafts_path(tool), params: { to: "friend@example.com", subject: "Plans", body: "<p>Hello</p>" } },
      announced(tool) { patch tool_mail_draft_path(tool, draft), params: { to: "friend@example.com", subject: "Other plans", body: "<p>Hello</p>" } },
      announced(tool) { post tool_mail_draft_attachments_path(tool, draft), params: upload.call, headers: { "Accept" => "application/json" } },
      announced(tool) { post tool_mails_path(tool), params: { to: "friend@example.com", subject: "Hello", body: "<p>Hi</p>" } },
      announced(tool) { delete tool_mail_path(tool, mails_messages(:trashed_message)) },
      announced(tool) { delete tool_empty_trash_path(tool) },
      announced(tool) { connect_to_imap(FakeImapServer.new(folders: [ "INBOX" ])) { post tool_folder_path(tool), params: { folder_name: "Clients" } } },
      announced(tool) { patch tool_mails_account_path(tool), params: { mails_account: { signature: "Best, Sem" } } },
      announced(unconnected) { post tool_mails_account_path(unconnected), params: { mails_account: account } }
    ]

    assert_empty writes_of("tools/mails") - tried, "These change a mailbox and aren't tried here"
  end

  test "mail that is read by opening it is read in every window, and a second look says nothing" do
    tool = tools(:my_mail)
    unread = mails_messages(:inbox_unread)

    assert_broadcasts(stream(tool), 1) { get tool_mail_path(tool, unread) }
    assert unread.reload.read?
    assert_no_broadcasts(stream(tool)) { get tool_mail_path(tool, unread) }
  end

  test "reading mail through the API leaves it unread, and says nothing" do
    tool = tools(:my_mail)

    assert_no_broadcasts(stream(tool)) { get tool_mail_path(tool, mails_messages(:inbox_unread)), as: :json }
    assert_not mails_messages(:inbox_unread).reload.read?
  end

  test "a change made with an access token is announced like any other" do
    tool = tools(:project_board)

    assert_broadcast_on(stream(tool), type: "changed", tool_id: tool.id) do
      post column_cards_path(columns(:todo)), params: { card: { title: "From a terminal" } }, headers: api_headers(@user), as: :json
    end
    assert_response :created
  end

  test "the announcement names the request, so the page that sent it knows its own" do
    tool = tools(:project_board)

    assert_broadcast_on(stream(tool), type: "changed", tool_id: tool.id, by: "a-request-of-mine") do
      post column_cards_path(columns(:todo)), params: { card: { title: "New" } }, headers: { "X-Turbo-Request-Id" => "a-request-of-mine" }, as: :json
    end
  end

  test "it says that something changed, and nothing of what" do
    tool = tools(:project_board)
    post column_cards_path(columns(:todo)), params: { card: { title: "Nobody else's business" } }, as: :json

    said = broadcasts(stream(tool)).map { |message| ActiveSupport::JSON.decode(message) }
    assert_equal [ { "type" => "changed", "tool_id" => tool.id } ], said
  end

  test "looking changes nothing, and neither does a change that was refused" do
    tool = tools(:project_board)

    assert_no_broadcasts(stream(tool)) do
      get tool_board_path(tool)
      get tool_board_path(tool), as: :json
      post column_cards_path(columns(:todo)), params: { card: { title: "" } }, as: :json
      assert_response :unprocessable_entity
    end
  end

  test "someone who isn't let into a tool announces nothing in it" do
    tool = tools(:project_board)
    sign_in_as users(:two)
    assert_not tool.accessible_by?(users(:two))

    assert_no_broadcasts(stream(tool)) do
      post column_cards_path(columns(:todo)), params: { card: { title: "Let me in" } }, as: :json
      assert_response :forbidden
    end
  end

  test "a column folded away for yourself is nobody else's to hear of" do
    tool = tools(:project_board)

    assert_no_broadcasts(stream(tool)) do
      patch tool_board_column_path(tool, columns(:todo)), params: { collapsed: true }, as: :json
      assert_response :ok
    end
  end

  test "what you have seen or read is your own" do
    assert_no_broadcasts(stream(tools(:project_board))) do
      post tool_visit_path(tools(:project_board))
      assert_response :no_content
    end
  end

  private
    def stream(tool)
      PresenceChannel.broadcasting_for(tool)
    end

    # Does what the block asks, checks that it went well and was announced once to the
    # tool's pages, and says which action it was
    def announced(tool, &request)
      assert_broadcasts(stream(tool), 1, &request)
      assert_operator response.status, :<, 400, "#{self.request.method} #{self.request.path} answered #{response.status}: #{response.body.first(200)}"

      "#{self.request.params[:controller]}##{self.request.params[:action]}"
    end

    # Every action that writes for someone who is let into a tool
    def writes
      Rails.application.eager_load!

      Rails.application.routes.routes.filter_map do |route|
        next unless WRITES.include?(route.verb)

        controller = "#{route.defaults[:controller]}_controller".camelize.safe_constantize
        action = route.defaults[:action]
        next unless controller && controller < ApplicationController && controller.include?(ToolAuthorization)

        [ controller, action ] if controller.action_methods.include?(action)
      end.uniq
    end

    # The actions under these namespaces that write and announce it
    def writes_of(*namespaces)
      writes.select { |controller, action| controller.announces_change?(action) }
        .map { |controller, action| "#{controller.controller_path}##{action}" }
        .select { |name| namespaces.any? { |namespace| name.start_with?("#{namespace}/") } }
    end
end

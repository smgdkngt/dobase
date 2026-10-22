# frozen_string_literal: true

require "test_helper"

# Every tool that changes something, through /mcp, with a token that may write.
class McpWriteToolsTest < ActionDispatch::IntegrationTest
  class FakeSmtp
    attr_reader :sent

    def initialize
      @sent = []
    end

    def send_email(**email)
      @sent << email
      true
    end
  end

  setup do
    @user = users(:one)
    @access_token = @user.access_tokens.create!(name: "Claude", permission: "write", agent: true)
    @token = @access_token.token
    @session = mcp_session(@token)
  end

  test "every tool that writes is tried in this file" do
    source = File.read(__FILE__)
    untried = Mcp::Tools.all.values.reject(&:read_only?).map(&:name).reject { source.include?(%("#{it}")) }
    assert_empty untried
  end

  test "a destructive tool does nothing without confirm, and says what to do" do
    card = cards(:first_task)
    message = call("card_delete", tool_id: tools(:project_board).id, card_id: card.id, confirm: false)
    assert_includes message, "confirm: true"
    assert Boards::Card.exists?(card.id)
  end

  test "a read-only connection can't write" do
    @access_token.update!(permission: "read")
    message = call("card_create", tool_id: tools(:project_board).id, title: "No")
    assert_includes message, "read-only"
    assert_equal "denied", Mcp::ToolCall.last.outcome
  end

  test "boards" do
    board = tools(:project_board)
    columns = board.board.columns.order(:position)

    card = call!("card_create", tool_id: board.id, title: "From Claude", description: "Line one\n\nSee https://example.com.",
      due: "tomorrow", assignee: "me", color: "green", column: columns.second.name)
    record = Boards::Card.find(card["id"])
    assert_equal columns.second, record.column
    assert_equal Date.tomorrow, record.due_date
    assert_equal @user, record.assigned_user
    assert_includes record.description.body.to_html, %(<a href="https://example.com">https://example.com</a>)

    call!("card_update", tool_id: board.id, card_id: record.id, title: "Renamed", due: "none", color: "none")
    assert_equal [ "Renamed", nil ], record.reload.then { [ it.title, it.due_date ] }

    moved = call!("card_move", tool_id: board.id, card_id: record.id, column: columns.first.id.to_s, position: 1)
    assert_equal [ columns.first.id, 0 ], [ record.reload.column_id, moved["position"] ]

    call!("card_archive", tool_id: board.id, card_id: record.id)
    assert record.reload.archived_at
    call!("card_unarchive", tool_id: board.id, card_id: record.id)
    assert_nil record.reload.archived_at

    comment = call!("card_comment", tool_id: board.id, card_id: record.id, text: "On it")
    assert_equal "Claude", record.comments.find(comment["id"]).via
    call!("card_uncomment", tool_id: board.id, card_id: record.id, comment_id: comment["id"], confirm: true)
    assert_empty record.comments.reload

    attached = call!("card_attach", tool_id: board.id, card_id: record.id, files: [ base64_file("notes.txt", "hello") ])
    assert_equal [ "notes.txt" ], attached["items"].pluck("filename")

    call!("card_delete", tool_id: board.id, card_id: record.id, confirm: true)
    assert_not Boards::Card.exists?(record.id)

    column = call!("column_create", tool_id: board.id, name: "Later")
    call!("column_rename", tool_id: board.id, column_id: column["id"], name: "Someday")
    assert_equal "Someday", Boards::Column.find(column["id"]).name
    call!("column_delete", tool_id: board.id, column_id: column["id"], confirm: true)
    assert_not Boards::Column.exists?(column["id"])
  end

  test "an unknown column or person says what there is" do
    board = tools(:project_board)
    assert_includes call("card_create", tool_id: board.id, title: "X", column: "Nowhere"), "there are:"
    assert_includes call("card_create", tool_id: board.id, title: "X", assignee: "nobody-at-all"), "Nobody"
  end

  test "todos" do
    todo = tools(:my_todos)
    item = call!("todo_create", tool_id: todo.id, title: "Call back", due: "today", repeat: "weekly")
    record = Todos::Item.find(item["id"])
    assert_equal [ "weekly", Date.current ], [ record.recurrence_rule, record.due_date ]

    call!("todo_update", tool_id: todo.id, todo_id: record.id, title: "Call Ann back", repeat: "none")
    assert_equal [ "Call Ann back", nil ], record.reload.then { [ it.title, it.recurrence_rule ] }

    call!("todo_finish", tool_id: todo.id, todo_id: record.id)
    assert record.reload.completed_at
    call!("todo_reopen", tool_id: todo.id, todo_id: record.id)
    assert_nil record.reload.completed_at

    list = call!("todolist_create", tool_id: todo.id, title: "Later")
    call!("todolist_rename", tool_id: todo.id, list_id: list["id"], title: "Someday")
    call!("todo_move", tool_id: todo.id, todo_id: record.id, list: "Someday")
    assert_equal list["id"], record.reload.todo_list_id

    comment = call!("todo_comment", tool_id: todo.id, todo_id: record.id, text: "<p>Done <b>soon</b></p>", html: true)
    assert_includes Todos::Comment.find(comment["id"]).body.to_s, "<b>soon</b>"
    call!("todo_uncomment", tool_id: todo.id, todo_id: record.id, comment_id: comment["id"], confirm: true)
    call!("todo_attach", tool_id: todo.id, todo_id: record.id, files: [ base64_file("list.csv", "a,b\n1,2\n") ])
    assert_equal 1, record.reload.attachments.count

    call!("todo_delete", tool_id: todo.id, todo_id: record.id, confirm: true)
    call!("todolist_delete", tool_id: todo.id, list_id: list["id"], confirm: true)
    assert_not Todos::List.exists?(list["id"])
  end

  test "docs" do
    docs = tools(:my_docs)
    document = call!("doc_create", tool_id: docs.id, title: "Plan", content: "Step one\nStep two")
    record = Docs::Document.find(document["id"])
    assert_includes record.content.to_s, "Step one<br>Step two"

    call!("doc_update", tool_id: docs.id, document_id: record.id, content: "<h1>Plan</h1>", html: true)
    assert_includes record.reload.content.to_s, "<h1>Plan</h1>"
    call!("doc_delete", tool_id: docs.id, document_id: record.id, confirm: true)
    assert_not Docs::Document.exists?(record.id)
  end

  test "chat" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { it.name = "Chat"; it.icon = "message-circle"; it.enabled = true }
    tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)

    message = call!("chat_post", tool_id: tool.id, text: "Hello")
    record = tool.chat.messages.find(message["id"])
    assert record.agent?

    with_file = call!("chat_post", tool_id: tool.id, reply_to_id: record.id, files: [ base64_file("a.txt", "file text") ])
    assert_equal 1, tool.chat.messages.find(with_file["id"]).files.count

    call!("chat_edit", tool_id: tool.id, message_id: record.id, text: "Hello all")
    assert_equal "Hello all", record.reload.body.to_plain_text
    call!("chat_react", tool_id: tool.id, message_id: record.id, emoji: "👍")
    call!("chat_react", tool_id: tool.id, message_id: record.id, emoji: "👍", remove: true)
    call!("chat_read", tool_id: tool.id)
    call!("chat_delete", tool_id: tool.id, message_id: record.id, confirm: true)
    assert_not tool.chat.messages.exists?(record.id)
  end

  test "workspace" do
    tool = call!("tool_create", name: "Ideas", type: "todos")
    call!("tool_rename", tool_id: tool["id"], name: "Good ideas")
    assert_equal "Good ideas", Tool.find(tool["id"]).name

    notification = @user.notifications.first
    call!("notification_read", notification_id: notification.id) if notification
    assert call!("notification_read").key?("marked_as_read")
  end

  test "calendar" do
    calendar = tools(:my_calendar)
    day = Date.tomorrow.iso8601
    appointment = call!("appointment_create", tool_id: calendar.id, title: "Flavor lab", starts: "#{day} 14:00", ends: "#{day} 15:00",
      location: "Kitchen", repeat: "weekly", repeat_ends: "count", repeat_count: 3)
    record = Calendars::Event.find(appointment["id"])
    assert_equal "Flavor lab", record.summary
    assert appointment["recurring"]

    call!("appointment_update", tool_id: calendar.id, appointment_id: record.id, title: "Flavor lab 2", repeat: "none")
    assert_equal "Flavor lab 2", record.reload.summary
    call!("appointment_delete", tool_id: calendar.id, appointment_id: record.id, confirm: true)
    assert_not Calendars::Event.exists?(record.id)
    assert call!("calendar_sync", tool_id: calendar.id).key?("status")
  end

  test "files" do
    files = tools(:my_files)
    folder = call!("folder_create", tool_id: files.id, name: "Notes")
    uploaded = call!("file_upload", tool_id: files.id, folder_id: folder["id"], files: [ base64_file("todo.md", "# Todo") ])
    file = uploaded["items"].sole
    assert_equal folder["id"], Files::Item.find(file["id"]).folder_id

    call!("file_rename", tool_id: files.id, file_id: file["id"], name: "done.md")
    call!("file_move", tool_id: files.id, file_id: file["id"])
    assert_equal [ "done.md", nil ], Files::Item.find(file["id"]).then { [ it.name, it.folder_id ] }

    other = call!("folder_create", tool_id: files.id, name: "Archive")
    call!("folder_rename", tool_id: files.id, folder_id: folder["id"], name: "Old notes")
    call!("folder_move", tool_id: files.id, folder_id: folder["id"], to_folder_id: other["id"])
    assert_equal other["id"], Files::Folder.find(folder["id"]).parent_id

    call!("file_delete", tool_id: files.id, file_id: file["id"], confirm: true)
    call!("folder_delete", tool_id: files.id, folder_id: other["id"], confirm: true)
    assert_not Files::Folder.exists?(folder["id"])
  end

  test "mail: flags, folders and the trash" do
    mails_accounts(:primary).update!(synced_folders: %w[INBOX Sent Trash].to_json)
    mail = tools(:my_mail)
    message = mails_messages(:inbox_unread)
    args = { tool_id: mail.id, mail_id: message.id }

    call!("mail_read", **args)
    assert message.reload.read
    call!("mail_unread", **args)
    call!("mail_star", **args)
    assert message.reload.starred
    call!("mail_unstar", **args)
    call!("mail_archive", **args)
    call!("mail_unarchive", **args)
    assert_includes call("mail_move", **args, folder: "trash"), "a view"
    call!("mail_trash", **args)
    assert message.reload.trashed?
    call!("mail_restore", **args)
    assert_not message.reload.trashed?
    assert call!("mail_sync", tool_id: mail.id).key?("status")
    assert call!("mail_sync_status", tool_id: mail.id).key?("status")
  end

  test "mail: junk where the server has a junk folder" do
    mail = tools(:my_mail)
    message = mails_messages(:inbox_read)
    mails_accounts(:primary).update!(synced_folders: %w[INBOX Sent Junk].to_json)
    call!("mail_junk", tool_id: mail.id, mail_id: message.id)
    assert_equal "Junk", message.reload.folder
    call!("mail_not_junk", tool_id: mail.id, mail_id: message.id)
    assert_equal "INBOX", message.reload.folder
  end

  test "mail: drafts, replies and forwards are drafts until mail_send sends one" do
    mails_accounts(:primary).update!(synced_folders: %w[INBOX Sent Drafts Trash].to_json)
    mail = tools(:my_mail)
    smtp = FakeSmtp.new
    SmtpSendService.singleton_class.define_method(:new) { |*| smtp }

    draft = call!("mail_draft", tool_id: mail.id, to: "ann@example.com", subject: "Hello", body: "Hi Ann",
      files: [ base64_file("offer.txt", "the offer") ])
    assert draft["draft"] || draft.dig("messages", 0, "draft") || draft["id"]
    draft_id = draft["id"]
    call!("mail_update", tool_id: mail.id, draft_id:, subject: "Hello again")
    assert_equal "Hello again", Mails::Message.find(draft_id).subject

    original = mails_messages(:inbox_unread)
    reply = call!("mail_reply", tool_id: mail.id, mail_id: original.id, body: "Thanks!", all: true)
    assert_equal "Re: #{original.subject.sub(/\ARe:\s*/i, "")}", reply["subject"]
    assert_equal [ original.from_address ], reply["to"]

    forward = call!("mail_forward", tool_id: mail.id, mail_id: original.id, to: "bob@example.com", body: "FYI")
    assert_match(/\AFwd: /, forward["subject"])
    call!("mail_discard", tool_id: mail.id, draft_id: forward["id"])
    assert Mails::Message.find(forward["id"]).trashed?

    assert_includes call("mail_send", tool_id: mail.id, draft_id:), "confirm: true"
    assert_empty smtp.sent
    sent = call!("mail_send", tool_id: mail.id, draft_id:, confirm: true)
    assert_equal [ "ann@example.com" ], sent["to"]
    assert_equal "Hello again", smtp.sent.sole[:subject]
    assert_equal [ "offer.txt" ], Array(smtp.sent.sole[:attachments]).map { it[:filename] || it["filename"] }
  ensure
    SmtpSendService.singleton_class.remove_method(:new) if SmtpSendService.singleton_class.method_defined?(:new, false)
  end

  private

  def call(name, **arguments)
    mcp_call(@token, @session, name, **arguments)
  end

  # Calls a tool and fails the test with its message when it didn't work
  def call!(name, **arguments)
    result = call(name, **arguments)
    assert_kind_of Hash, result, "#{name}: #{result}"
    result
  end

  def base64_file(name, content)
    { name:, content_base64: Base64.strict_encode64(content) }
  end
end

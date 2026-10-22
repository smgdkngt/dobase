# frozen_string_literal: true

require "test_helper"

# Every tool that reads, through /mcp, as the CLI and Claude call it: the JSON
# API's answer comes back as structured content and as text.
class McpReadToolsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @token = @user.access_tokens.create!(name: "Claude", permission: "read").token
    @session = mcp_session(@token)
  end

  test "every tool that only reads says so, and nothing else does" do
    tools = mcp_request(@token, @session, "tools/list").dig("result", "tools").index_by { it["name"] }
    Mcp::Tools.all.each_value do |tool|
      assert_equal tool.read_only?, tools.dig(tool.name, "annotations", "readOnlyHint"), tool.name
      assert_equal tool.destructive?, tools.dig(tool.name, "annotations", "destructiveHint"), tool.name
    end
  end

  test "a result is structured content and the same JSON as text" do
    result = mcp_request(@token, @session, "tools/call", { name: "whoami", arguments: {} })["result"]
    assert_equal @user.email_address, result.dig("structuredContent", "email_address")
    assert_equal result["structuredContent"], JSON.parse(result.dig("content", 0, "text"))
  end

  test "workspace" do
    assert_includes mcp_call(@token, @session, "tool_list")["items"].pluck("name"), tools(:project_board).name
    assert_equal "Project Board", mcp_call(@token, @session, "tool_show", tool_id: tools(:project_board).id)["name"]
    assert mcp_call(@token, @session, "search", query: cards(:first_task).title)["results"].any?
    assert_kind_of Array, mcp_call(@token, @session, "notification_list", unread: true, limit: 5)["items"]
    assert mcp_call(@token, @session, "event_list").key?("cursor")
  end

  test "boards" do
    board = tools(:project_board)
    columns = mcp_call(@token, @session, "card_list", tool_id: board.id)["columns"]
    assert_includes columns.flat_map { it["cards"] }.pluck("id"), cards(:first_task).id
    assert_equal cards(:first_task).title, mcp_call(@token, @session, "card_show", tool_id: board.id, card_id: cards(:first_task).id)["title"]
  end

  test "todos" do
    todo = tools(:my_todos)
    lists = mcp_call(@token, @session, "todo_list", tool_id: todo.id)["lists"]
    assert_includes lists.flat_map { it["items"] }.pluck("id"), todo_items(:pending_one).id
    assert_equal todo_items(:pending_one).title,
      mcp_call(@token, @session, "todo_show", tool_id: todo.id, todo_id: todo_items(:pending_one).id)["title"]
  end

  test "docs" do
    docs = tools(:my_docs)
    assert_includes mcp_call(@token, @session, "doc_list", tool_id: docs.id)["documents"].pluck("id"), docs_documents(:meeting_notes).id
    assert_equal docs_documents(:meeting_notes).title,
      mcp_call(@token, @session, "doc_show", tool_id: docs.id, document_id: docs_documents(:meeting_notes).id)["title"]
  end

  test "chat" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { it.name = "Chat"; it.icon = "message-circle"; it.enabled = true }
    tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    tool.chat.messages.create!(user: @user, body: "Hello from the test")

    messages = mcp_call(@token, @session, "chat_list", tool_id: tool.id, limit: 10)["messages"]
    assert_equal [ "Hello from the test" ], messages.pluck("body")
  end

  test "mail leaves the HTML out unless asked" do
    mail = tools(:my_mail)
    listing = mcp_call(@token, @session, "mail_list", tool_id: mail.id)
    assert_includes listing["conversations"].pluck("id"), mails_messages(:inbox_unread).id

    conversation = mcp_call(@token, @session, "mail_show", tool_id: mail.id, mail_id: mails_messages(:inbox_unread).id)
    assert conversation["messages"].none? { it.key?("body_html") }
    with_html = mcp_call(@token, @session, "mail_show", tool_id: mail.id, mail_id: mails_messages(:inbox_unread).id, include_html: true)
    assert with_html["messages"].all? { it.key?("body_html") }
    assert_not mails_messages(:inbox_unread).reload.read?, "reading through MCP doesn't mark mail read"

    assert_kind_of Array, mcp_call(@token, @session, "mail_contacts", tool_id: mail.id, query: "a")["items"]
  end

  test "calendar" do
    calendar = tools(:my_calendar)
    event = calendars_events(:meeting)
    agenda = mcp_call(@token, @session, "appointment_list", tool_id: calendar.id,
      start_date: event.starts_at.to_date.iso8601, end_date: (event.starts_at.to_date + 1).iso8601)
    assert_includes agenda["events"].pluck("id"), event.id
    assert_equal event.summary, mcp_call(@token, @session, "appointment_show", tool_id: calendar.id, appointment_id: event.id)["summary"]
  end

  test "files, and what is in one" do
    files = tools(:my_files)
    item = file_items(:readme)
    item.file.attach(io: StringIO.new("# Read me\n\nHello."), filename: "README.md", content_type: "text/markdown")

    assert_includes mcp_call(@token, @session, "file_list", tool_id: files.id)["files"].pluck("id"), item.id
    shown = mcp_call(@token, @session, "file_show", tool_id: files.id, file_id: item.id)
    preview_id = shown["preview_url"][%r{file_previews/(\d+)}, 1].to_i
    read = mcp_call(@token, @session, "file_read", tool_id: files.id, preview_id:)
    assert_includes read["text"], "Hello."
  end

  test "another person's tool is not found, and the refusal is logged" do
    message = mcp_call(@token, @session, "todo_list", tool_id: tools(:other_todos).id)
    assert_kind_of String, message
    assert_includes %w[denied error], Mcp::ToolCall.last.outcome
  end

  test "arguments that don't fit the tool are refused before it runs" do
    result = mcp_request(@token, @session, "tools/call", { name: "card_show", arguments: { tool_id: "abc" } })
    assert(result["error"] || result.dig("result", "isError"))
  end

  test "the call log keeps what was asked, capped" do
    mcp_call(@token, @session, "search", query: "x" * 5_000)
    call = Mcp::ToolCall.last
    assert_equal "search", call.tool
    assert call.arguments.key?("truncated")
    assert_operator call.duration_ms, :>=, 0
  end
end

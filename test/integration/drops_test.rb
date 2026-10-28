# frozen_string_literal: true

require "test_helper"

# Something dragged from one place in Dobase onto another (Dropped, drag_drop_controller.js):
# the place's own create makes something of it
class DropsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @mail = mails_messages(:inbox_unread)
    @mail.attachments.create!(filename: "notes.txt", content_type: "text/plain", file_size: 5)
      .file.attach(io: StringIO.new("notes"), filename: "notes.txt", content_type: "text/plain")
  end

  test "a mail dropped on a column is a card with a link back to it, a few of its words and its files" do
    assert_difference -> { columns(:todo).cards.count } do
      post column_cards_path(columns(:todo)), params: { dropped: Dropped.sgid_for(@mail) }, as: :json
    end
    assert_response :created

    card = columns(:todo).cards.last
    assert_equal @mail.subject, card.title
    assert_includes card.description.to_s, "/tools/#{@mail.account.tool_id}/mails/#{@mail.id}"
    assert_equal [ "notes.txt" ], card.attachments.map(&:filename)
    assert_equal @mail.attachments.first.file.blob, card.attachments.first.file.blob
  end

  test "a card dropped on a todo list is a todo" do
    card = cards(:first_task)

    post todo_list_items_path(todo_lists(:main)), params: { dropped: Dropped.sgid_for(card) }, as: :json

    assert_response :created
    assert_equal card.title, todo_lists(:main).items.order(:id).last.title
  end

  test "a file dropped on a chat is a message with the file" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.name = "Chat"; type.icon = "message-circle"; type.enabled = true }
    chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user)
    file = file_items(:readme)
    file.file.attach(io: StringIO.new("read me"), filename: "readme.txt", content_type: "text/plain") unless file.file.attached?

    post tool_chat_messages_path(chat), params: { dropped: Dropped.sgid_for(file) }, as: :json

    message = chat.chat.messages.last
    assert_equal [ "readme.txt" ], message.files.map { |attached| attached.filename.to_s }
    assert_includes message.body.to_s, file.name
  end

  test "a mail dropped on the files keeps its files there" do
    tool = tools(:my_files)

    assert_difference -> { tool.file_items.count } do
      post tool_files_uploads_path(tool), params: { dropped: Dropped.sgid_for(@mail) }, as: :json
    end
    assert_equal "notes.txt", tool.file_items.order(:id).last.name
  end

  test "a card dropped on the mail tool is a draft about it" do
    card = cards(:first_task)

    post tool_mail_drafts_path(tools(:my_mail)), params: { dropped: Dropped.sgid_for(card) }, as: :json

    assert_response :created
    draft = Mails::Message.find(response.parsed_body["id"])
    assert draft.draft?
    assert_equal card.title, draft.subject
  end

  test "something dropped on a tool in the menu goes on to where that tool makes things" do
    post tool_drops_path(tools(:project_board)), params: { dropped: Dropped.sgid_for(@mail) }, as: :json

    assert_response :temporary_redirect
    assert_redirected_to column_cards_path(tools(:project_board).board.columns.first)
  end

  test "nothing can be made of what the one who drops it can't see" do
    theirs = Mails::Message.where(account: mails_accounts(:other)).first ||
      mails_accounts(:other).messages.create!(message_id: "theirs@example.com", folder: "INBOX", subject: "Theirs")

    assert_no_difference -> { Boards::Card.count } do
      post column_cards_path(columns(:todo)), params: { dropped: Dropped.sgid_for(theirs) }, as: :json
    end
    assert_response :not_found
  end

  test "a signed id for something else than dragging isn't taken" do
    assert_no_difference -> { Boards::Card.count } do
      post column_cards_path(columns(:todo)), params: { dropped: @mail.to_sgid(for: "something else").to_s }, as: :json
    end
    assert_response :not_found
  end
end

# frozen_string_literal: true

require "test_helper"

class NotifierMessagesTest < ActiveSupport::TestCase
  setup do
    @actor = users(:one)
    @recipient = users(:two)
    @tool = tools(:shared_board)
    @card = cards(:first_task)
    @column = columns(:in_progress)
    @file = file_items(:report)
    @todo = todo_items(:pending_one)
    @todo_comment = todo_comments(:first_comment)
    @calendar_event = Calendars::Event.find_by!(uid: "meeting-123@dobase")
  end

  test "card assignment renders message, url, and tool_id" do
    notification = deliver CardAssignmentNotifier, card: @card, assigner: @actor, tool: @tool

    assert_equal "#{@actor.name} assigned you to #{@card.title}", notification.message
    assert_equal "/tools/#{@tool.id}/board?card=#{@card.id}", notification.url
    assert_equal @tool.id, notification.notification_data[:tool_id]
    assert_equal "CardAssignmentNotifier", notification.notification_data[:type]
  end

  test "card comment renders message and url" do
    comment = Boards::Comment.create!(card: @card, user: @actor, body: "Nice")

    notification = deliver CardCommentNotifier, comment: comment, commenter: @actor, card: @card, tool: @tool

    assert_equal "#{@actor.name} commented on #{@card.title}", notification.message
    assert_equal "/tools/#{@tool.id}/board?card=#{@card.id}", notification.url
  end

  test "card moved includes column name" do
    notification = deliver CardMovedNotifier, card: @card, mover: @actor, tool: @tool, column: @column

    assert_equal "#{@actor.name} moved #{@card.title} to #{@column.name}", notification.message
  end

  test "chat message links to the chat tool" do
    notification = deliver ChatMessageNotifier, message: @card, sender: @actor, tool: @tool

    assert_equal "#{@actor.name} sent a message in #{@tool.name}", notification.message
    assert_equal "/tools/#{@tool.id}/chat", notification.url
  end

  test "tool invitation links to the acceptance path" do
    invitation = Invitation.create!(tool: @tool, email: "guest@example.com", invited_by: @actor)

    notification = deliver ToolInvitationNotifier,
      invitation: invitation, tool: @tool, invited_by: @actor, recipient_user: @recipient

    assert_equal "#{@actor.name} invited you to collaborate on #{@tool.name}", notification.message
    assert_equal "/invitations/#{invitation.token}/accept", notification.url
  end

  test "file uploaded renders file name" do
    notification = deliver FileUploadedNotifier, file: @file, uploader: @actor, tool: @tool

    assert_equal "#{@actor.name} uploaded #{@file.name}", notification.message
    assert_equal "/tools/#{@tool.id}/files", notification.url
  end

  test "document created links to the document" do
    document = Docs::Document.create!(tool: @tool, title: "Roadmap", created_by: @actor, updated_by: @actor)

    notification = deliver DocumentCreatedNotifier, document: document, creator: @actor, tool: @tool

    assert_equal "#{@actor.name} created #{document.title}", notification.message
    assert_equal "/tools/#{@tool.id}/docs/documents/#{document.id}", notification.url
  end

  test "calendar event formats start_time as month and day" do
    notification = deliver CalendarEventCreatedNotifier, event: @calendar_event, creator: @actor, tool: @tool

    expected_date = @calendar_event.start_time.strftime("%b %-d")
    assert_equal "#{@actor.name} created #{@calendar_event.summary} on #{expected_date}", notification.message
    assert_equal "/tools/#{@tool.id}/calendar", notification.url
  end

  test "todo assignment renders message and links to item" do
    notification = deliver TodoAssignmentNotifier, item: @todo, assigner: @actor, tool: @tool

    assert_equal "#{@actor.name} assigned you to #{@todo.title}", notification.message
    assert_equal "/tools/#{@tool.id}/todo?item=#{@todo.id}", notification.url
  end

  test "todo comment renders message" do
    notification = deliver TodoCommentNotifier, comment: @todo_comment, commenter: @actor, item: @todo, tool: @tool

    assert_equal "#{@actor.name} commented on #{@todo.title}", notification.message
  end

  test "todo completed renders message" do
    notification = deliver TodoCompletedNotifier, item: @todo, completer: @actor, tool: @tool

    assert_equal "#{@actor.name} completed #{@todo.title}", notification.message
  end

  # Nil-safety: referenced records may be deleted before the recipient sees the
  # notification. The notifier must render without raising and fall back to
  # generic copy. This invariant is called out explicitly in CLAUDE.md.
  test "card notifiers tolerate deleted card and assigner" do
    notification = deliver CardAssignmentNotifier, card: nil, assigner: nil, tool: @tool

    assert_equal "Someone assigned you to a card", notification.message
    assert_equal "/tools/#{@tool.id}/board", notification.url
  end

  test "card moved tolerates deleted column" do
    notification = deliver CardMovedNotifier, card: nil, mover: nil, tool: @tool, column: nil

    assert_equal "Someone moved a card to a column", notification.message
  end

  test "chat notifier tolerates deleted tool" do
    notification = deliver ChatMessageNotifier, message: nil, sender: nil, tool: nil

    assert_equal "Someone sent a message in a chat", notification.message
    assert_equal "/", notification.url
    assert_nil notification.notification_data[:tool_id]
  end

  test "tool invitation tolerates missing invitation" do
    notification = deliver ToolInvitationNotifier,
      invitation: nil, tool: nil, invited_by: nil, recipient_user: @recipient

    assert_equal "Someone invited you to collaborate on a tool", notification.message
    assert_equal "/", notification.url
  end

  test "document notifier tolerates missing document" do
    notification = deliver DocumentCreatedNotifier, document: nil, creator: nil, tool: @tool

    assert_equal "Someone created a document", notification.message
    assert_equal "/", notification.url
  end

  test "calendar event tolerates missing event and start_time" do
    notification = deliver CalendarEventCreatedNotifier, event: nil, creator: nil, tool: @tool

    assert_equal "Someone created an event on a date", notification.message
  end

  test "file uploaded tolerates missing file" do
    notification = deliver FileUploadedNotifier, file: nil, uploader: nil, tool: @tool

    assert_equal "Someone uploaded a file", notification.message
  end

  test "todo assignment tolerates missing item" do
    notification = deliver TodoAssignmentNotifier, item: nil, assigner: nil, tool: @tool

    assert_equal "Someone assigned you to a todo", notification.message
  end

  test "todo completed tolerates missing item" do
    notification = deliver TodoCompletedNotifier, item: nil, completer: nil, tool: @tool

    assert_equal "Someone completed a todo", notification.message
  end

  private
    def deliver(notifier_class, **params)
      notifier_class.with(**params).deliver(@recipient)
      @recipient.notifications.reload.last
    end
end

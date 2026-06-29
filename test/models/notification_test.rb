# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @user_one = users(:one)
    @user_two = users(:two)
    @tool = tools(:shared_board)
  end

  test "chat message notifies other collaborators but not sender" do
    chat = Chats::Chat.create!(tool: @tool)

    assert_difference -> { @user_two.notifications.count }, 1 do
      assert_no_difference -> { @user_one.notifications.count } do
        Chats::Message.create!(chat: chat, user: @user_one, body: "Hello!")
      end
    end
  end

  test "card comment notifies other collaborators but not commenter" do
    # Use shared_board which has both user_one (owner) and user_two (collaborator)
    board = boards(:shared)
    column = board.columns.create!(name: "Test", position: 0)
    card = column.cards.create!(title: "Shared card", position: 0)

    assert_difference -> { @user_two.notifications.count }, 1 do
      assert_no_difference -> { @user_one.notifications.count } do
        Boards::Comment.create!(card: card, user: @user_one, body: "Nice work!")
      end
    end
  end

  test "mentioning a collaborator sends a mention notification instead of the generic one" do
    chat = Chats::Chat.create!(tool: @tool)
    body = %(<p>hey <span data-id="#{@user_two.id}" class="mention">@User Two</span></p>)

    assert_difference -> { @user_two.notifications.count }, 1 do
      Chats::Message.create!(chat: chat, user: @user_one, body: body)
    end

    assert_equal "MentionNotifier", @user_two.notifications.order(:created_at).last.event.type
  end

  test "a mentioned user is not double-notified with the generic chat notifier" do
    chat = Chats::Chat.create!(tool: @tool)
    body = %(<p><span data-id="#{@user_two.id}" class="mention">@User Two</span> ping</p>)

    assert_difference -> { @user_two.notifications.count }, 1 do
      Chats::Message.create!(chat: chat, user: @user_one, body: body)
    end

    types = @user_two.notifications.map { |n| n.event.type }
    refute_includes types, "ChatMessageNotifier"
  end

  test "non-mentioned collaborators still get the generic notification" do
    third = User.create!(first_name: "Third", last_name: "User", email_address: "third@example.com", password: "password123")
    @tool.collaborators.create!(user: third, role: "collaborator")
    chat = Chats::Chat.create!(tool: @tool)
    body = %(<p><span data-id="#{@user_two.id}" class="mention">@User Two</span> hi</p>)

    Chats::Message.create!(chat: chat, user: @user_one, body: body)

    assert_equal "MentionNotifier", @user_two.notifications.order(:created_at).last.event.type
    assert_equal "ChatMessageNotifier", third.notifications.order(:created_at).last.event.type
  end

  test "card comment mention links to the card and notifies the mentioned user" do
    board = boards(:shared)
    column = board.columns.create!(name: "Test", position: 0)
    card = column.cards.create!(title: "Shared card", position: 0)
    body = %(<p><span data-id="#{@user_two.id}" class="mention">@User Two</span> look</p>)

    assert_difference -> { @user_two.notifications.count }, 1 do
      Boards::Comment.create!(card: card, user: @user_one, body: body)
    end

    notification = @user_two.notifications.order(:created_at).last
    assert_equal "MentionNotifier", notification.event.type
    assert_includes notification.event.params[:url], "card=#{card.id}"
  end

  test "card assignment notifies assignee" do
    card = cards(:first_task)

    assert_difference -> { @user_two.notifications.count }, 1 do
      CardAssignmentNotifier.with(
        card: card,
        assigner: @user_one,
        tool: @tool
      ).deliver(@user_two)
    end
  end

  test "tool invitation notifies existing user" do
    assert_difference -> { @user_two.notifications.count }, 1 do
      ToolInvitationNotifier.with(
        invitation: "test",
        tool: @tool,
        invited_by: @user_one,
        recipient_user: @user_two
      ).deliver(@user_two)
    end
  end

  test "user has_many notifications" do
    assert_respond_to @user_one, :notifications
  end

  test "muted collaborator does not receive chat notifications" do
    chat = Chats::Chat.create!(tool: @tool)
    collaborators(:two_shared_board).mute!

    assert_no_difference -> { @user_two.notifications.count } do
      Chats::Message.create!(chat: chat, user: @user_one, body: "Hello!")
    end
  end

  test "muted collaborator does not receive card comment notifications" do
    board = boards(:shared)
    column = board.columns.create!(name: "Test", position: 0)
    card = column.cards.create!(title: "Shared card", position: 0)
    collaborators(:two_shared_board).mute!

    assert_no_difference -> { @user_two.notifications.count } do
      Boards::Comment.create!(card: card, user: @user_one, body: "Nice work!")
    end
  end

  test "muted tool is excluded from unread_tool_ids_for" do
    board = boards(:shared)
    column = board.columns.create!(name: "Test", position: 0)
    column.cards.create!(title: "Fresh card", position: 0)

    refute_nil Tool.unread_tool_ids_for(@user_two).find { |id| id == @tool.id }

    collaborators(:two_shared_board).mute!

    assert_nil Tool.unread_tool_ids_for(@user_two).find { |id| id == @tool.id }
  end

  test "notifications are destroyed with user" do
    user = User.create!(first_name: "Temp", last_name: "User", email_address: "temp@example.com", password: "password123")

    ChatMessageNotifier.with(
      message: "test",
      sender: @user_one,
      tool: @tool
    ).deliver(user)

    assert user.notifications.any?

    assert_difference "Noticed::Notification.count", -1 do
      user.destroy!
    end
  end
end

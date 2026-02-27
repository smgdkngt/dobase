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

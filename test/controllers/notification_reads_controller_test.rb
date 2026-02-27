# frozen_string_literal: true

require "test_helper"

class NotificationReadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user

    ChatMessageNotifier.with(
      message: "test",
      sender: users(:two),
      tool: tools(:shared_board)
    ).deliver(@user)
  end

  test "create marks all notifications as read" do
    assert @user.notifications.unread.any?

    post notification_reads_path

    assert_response :success
    assert_equal 0, @user.notifications.unread.count
  end

  test "create requires authentication" do
    sign_out

    post notification_reads_path

    assert_redirected_to new_session_path
  end
end

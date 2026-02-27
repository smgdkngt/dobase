# frozen_string_literal: true

require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "index returns notifications" do
    # Create a notification for the user
    event = ChatMessageNotifier.with(
      message: "test",
      sender: users(:two),
      tool: tools(:shared_board)
    ).deliver(@user)

    get notifications_path

    assert_response :success
  end

  test "index returns empty state when no notifications" do
    get notifications_path

    assert_response :success
    assert_includes response.body, "No notifications"
  end

  test "index requires authentication" do
    sign_out

    get notifications_path

    assert_redirected_to new_session_path
  end
end

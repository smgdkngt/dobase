# frozen_string_literal: true

require "test_helper"

module Notifications
  class ReadsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as @user

      ChatMessageNotifier.with(
        message: "test",
        sender: users(:two),
        tool: tools(:shared_board)
      ).deliver(@user)

      @notification = @user.notifications.last
    end

    test "create marks notification as read" do
      assert_nil @notification.read_at

      post notification_read_path(@notification)

      assert_response :success
      assert_not_nil @notification.reload.read_at
    end

    test "create requires authentication" do
      sign_out

      post notification_read_path(@notification)

      assert_redirected_to new_session_path
    end
  end
end

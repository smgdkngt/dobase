# frozen_string_literal: true

require "test_helper"

# The sidebar notification badge's visibility must be correct straight out of
# the server response, not just after notifications_controller.js patches it
# client-side on connect — a Turbo morph refresh (e.g. after ticking a todo
# or adding a card) restores whatever class the server sends, so a badge that
# is always server-rendered "hidden" gets reset even when there are unread
# notifications, until the next full page load runs the JS again.
class NotificationsBadgeRenderingTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "the badge is rendered hidden when there are no unread notifications" do
    assert_equal 0, @user.notifications.unread.count

    get tool_files_path(tools(:my_files))

    badge = Nokogiri::HTML(response.body).at_css("[data-notifications-target='badge']")
    assert badge, "expected a notification badge in the response"
    assert_includes badge["class"].split, "hidden"
  end

  test "the badge is rendered visible, with the right count, when there are unread notifications" do
    other = users(:two)
    tool = tools(:shared_board)
    Chats::Message.create!(chat: Chats::Chat.create!(tool: tool), user: other, body: "Hello there")
    assert_equal 1, @user.reload.notifications.unread.count

    get tool_files_path(tools(:my_files))

    badge = Nokogiri::HTML(response.body).at_css("[data-notifications-target='badge']")
    assert badge, "expected a notification badge in the response"
    assert_not_includes badge["class"].split, "hidden"
    assert_equal "1", badge.text.strip
  end
end

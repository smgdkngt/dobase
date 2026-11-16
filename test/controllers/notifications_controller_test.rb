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

  test "the bell shows all with the unread first, or only the unread, and leads to the page" do
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Label", position: 0)
    CardAssignmentNotifier.with(card: card, assigner: users(:two), tool: tools(:shared_board)).deliver(@user)
    @user.notifications.update_all(read_at: Time.current)
    CardMovedNotifier.with(card: card, mover: users(:two), tool: tools(:shared_board), column: card.column).deliver(@user)

    get notifications_path, headers: { "Turbo-Frame" => "notifications" }

    assert_select "turbo-frame#notifications"
    assert_select ".notification-row", count: 2
    assert_select ".notification-row:first-child.notification-row-unread"
    assert_select ".tab.active", text: "All"
    assert_select "a[href='#{notifications_path}'][data-turbo-frame='_top']", text: "View all"
    assert_select "a, button", text: "Clear all", count: 0

    get notifications_path(filter: "unread"), headers: { "Turbo-Frame" => "notifications" }

    assert_select ".notification-row", count: 1
    assert_select ".tab.active", text: "Unread"
  end

  test "the page lists what is kept, a page at a time, and clears it" do
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Label", position: 0)
    25.times { CardAssignmentNotifier.with(card: card, assigner: users(:two), tool: tools(:shared_board)).deliver(@user) }

    get notifications_path

    assert_response :success
    assert_select "h1", text: "Notifications"
    assert_select ".notification-row", count: 20
    assert_select "a[href='#{notifications_path(page: 2)}']", text: "Older"
    assert_select "a[href='#{notification_clears_path}'][data-turbo-confirm]", text: "Clear all"

    get notifications_path(page: 2)

    assert_select ".notification-row", count: 5
    assert_select "a[href='#{notifications_path}']", text: "Newer"

    post notification_clears_path

    assert_redirected_to notifications_path
    assert_equal 0, @user.notifications.count
  end

  test "index requires authentication" do
    sign_out

    get notifications_path

    assert_redirected_to new_session_path
  end
end

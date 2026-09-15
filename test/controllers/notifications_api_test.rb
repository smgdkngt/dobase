# frozen_string_literal: true

require "test_helper"

class NotificationsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)
    @headers = api_headers(@user)
    @tool = tools(:shared_board)
  end

  test "index lists notifications newest first" do
    older = notify(CardAssignmentNotifier, at: 2.hours.ago, card: cards(:first_task), assigner: @other_user, tool: @tool)
    newer = notify(ChatMessageNotifier, at: 1.hour.ago, message: nil, sender: @other_user, tool: @tool)
    older.mark_as_read!

    get notifications_path, headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_equal [ newer.id, older.id ], body.map { |notification| notification["id"] }

    assert_equal "ChatMessageNotifier", body.first["type"]
    assert_equal "User Two sent a message in Shared Board", body.first["message"]
    assert_equal "http://www.example.com/tools/#{@tool.id}/chat", body.first["url"]
    assert_equal @tool.id, body.first["tool_id"]
    assert_equal false, body.first["read"]
    assert_nil body.first["read_at"]
    assert_not_nil body.first["created_at"]

    assert_equal "CardAssignmentNotifier", body.last["type"]
    assert_equal "http://www.example.com/tools/#{@tool.id}/board?card=#{cards(:first_task).id}", body.last["url"]
    assert_equal true, body.last["read"]
    assert_not_nil body.last["read_at"]
  end

  test "index with unread=true leaves out read notifications" do
    read = notify(ChatMessageNotifier, at: 2.hours.ago, message: nil, sender: @other_user, tool: @tool)
    unread = notify(ChatMessageNotifier, at: 1.hour.ago, message: nil, sender: @other_user, tool: @tool)
    read.mark_as_read!

    get notifications_path(unread: true), headers: @headers

    assert_equal [ unread.id ], response.parsed_body.map { |notification| notification["id"] }
  end

  test "index returns 20 notifications by default and at most 100" do
    105.times { |index| notify(ChatMessageNotifier, at: (105 - index).minutes.ago, message: nil, sender: @other_user, tool: @tool) }

    get notifications_path, headers: @headers
    assert_equal 20, response.parsed_body.size

    get notifications_path(limit: 5), headers: @headers
    assert_equal 5, response.parsed_body.size

    get notifications_path(limit: 500), headers: @headers
    assert_equal 100, response.parsed_body.size

    get notifications_path(limit: [ "5" ]), headers: @headers
    assert_response :success
    assert_equal 20, response.parsed_body.size
  end

  test "index only lists your own notifications" do
    notify(ChatMessageNotifier, recipient: @other_user, message: nil, sender: @user, tool: @tool)

    get notifications_path, headers: @headers

    assert_equal [], response.parsed_body
  end

  test "read marks one notification read" do
    notification = notify(ChatMessageNotifier, message: nil, sender: @other_user, tool: @tool)
    other = notify(ChatMessageNotifier, message: nil, sender: @other_user, tool: @tool)

    post notification_read_path(notification), headers: @headers, as: :json

    assert_response :success
    assert_equal notification.id, response.parsed_body["id"]
    assert_equal true, response.parsed_body["read"]
    assert notification.reload.read?
    assert other.reload.unread?
  end

  test "read refuses someone else's notification" do
    notification = notify(ChatMessageNotifier, recipient: @other_user, message: nil, sender: @user, tool: @tool)

    post notification_read_path(notification), headers: @headers, as: :json

    assert_response :not_found
    assert notification.reload.unread?
  end

  test "reads marks all notifications read" do
    2.times { notify(ChatMessageNotifier, message: nil, sender: @other_user, tool: @tool) }
    notify(ChatMessageNotifier, message: nil, sender: @other_user, tool: @tool).mark_as_read!
    someone_elses = notify(ChatMessageNotifier, recipient: @other_user, message: nil, sender: @user, tool: @tool)

    post notification_reads_path, headers: @headers, as: :json

    assert_response :success
    assert_equal({ "marked_as_read" => 2 }, response.parsed_body)
    assert_equal 0, @user.notifications.unread.count
    assert someone_elses.reload.unread?
  end

  test "read-only tokens can list notifications but not mark them read" do
    notification = notify(ChatMessageNotifier, message: nil, sender: @other_user, tool: @tool)
    headers = api_headers(@user, permission: "read")

    get notifications_path, headers: headers
    assert_response :success

    post notification_read_path(notification), headers: headers, as: :json
    assert_response :forbidden

    post notification_reads_path, headers: headers, as: :json
    assert_response :forbidden
    assert notification.reload.unread?
  end

  test "tokens can't clear notifications" do
    notify(ChatMessageNotifier, message: nil, sender: @other_user, tool: @tool)

    assert_no_difference -> { @user.notifications.count } do
      post notification_clears_path, headers: @headers, as: :json
    end

    assert_response :forbidden
  end

  private

  def notify(notifier, recipient: @user, at: Time.current, **params)
    travel_to(at) { notifier.with(**params).deliver(recipient) }
    recipient.notifications.order(:id).last
  end
end

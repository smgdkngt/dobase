# frozen_string_literal: true

require "test_helper"

class NotificationDigestMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:two)
    @actor = users(:one)
    @tool = tools(:shared_board)
    @card = cards(:first_task)
  end

  test "digest singular subject when there is one notification" do
    notifications = deliver_notifications(1)

    mail = NotificationDigestMailer.digest(@user, notifications)

    assert_equal [ @user.email_address ], mail.to
    assert_equal "1 new notification from #{Rails.application.config.x.app.name}", mail.subject
  end

  test "digest plural subject when there are multiple notifications" do
    notifications = deliver_notifications(3)

    mail = NotificationDigestMailer.digest(@user, notifications)

    assert_equal "3 new notifications from #{Rails.application.config.x.app.name}", mail.subject
  end

  test "digest body lists every notification message" do
    notifications = deliver_notifications(2)

    mail = NotificationDigestMailer.digest(@user, notifications)
    body = mail.text_part.body.to_s

    notifications.each do |notification|
      assert_includes body, notification.message
    end
  end

  test "digest body groups notifications by tool name" do
    notifications = deliver_notifications(2)

    mail = NotificationDigestMailer.digest(@user, notifications)

    assert_includes mail.text_part.body.to_s, "[#{@tool.name}]"
  end

  test "digest body includes absolute urls to each notification target" do
    notifications = deliver_notifications(1)

    mail = NotificationDigestMailer.digest(@user, notifications)
    body = mail.text_part.body.to_s

    assert_match %r{http://example\.com/tools/#{@tool.id}/board}, body
  end

  test "digest includes a comment preview when the notification references one" do
    comment = Boards::Comment.create!(card: @card, user: @actor, body: "Looks great, ship it.")
    CardCommentNotifier.with(comment: comment, commenter: @actor, card: @card, tool: @tool).deliver(@user)
    notifications = @user.notifications.reload.last(1)

    mail = NotificationDigestMailer.digest(@user, notifications)

    assert_includes mail.text_part.body.to_s, "Looks great, ship it."
  end

  test "digest includes a link to change digest frequency" do
    mail = NotificationDigestMailer.digest(@user, deliver_notifications(1))

    assert_includes mail.text_part.body.to_s, "http://example.com/profile/edit"
  end

  private
    def deliver_notifications(count)
      count.times do
        CardAssignmentNotifier.with(card: @card, assigner: @actor, tool: @tool).deliver(@user)
      end
      @user.notifications.reload.last(count)
    end
end

# frozen_string_literal: true

require "test_helper"

class NotificationDigestJobTest < ActiveJob::TestCase
  setup do
    @user = users(:two)
    @user.update!(notification_digest: "1_hour", last_notification_digest_at: nil)
    @chat = Chats::Chat.create!(tool: tools(:shared_board))
  end

  test "digests the unread notifications" do
    Chats::Message.create!(chat: @chat, user: users(:one), body: "Hello!")

    perform_enqueued_jobs { NotificationDigestJob.perform_now }

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email_address ], mail.to
    assert_match "sent a message", mail.html_part.body.to_s
  end

  test "a notification cleared before the mail goes out doesn't sink the digest" do
    Chats::Message.create!(chat: @chat, user: users(:one), body: "First")
    Chats::Message.create!(chat: @chat, user: users(:one), body: "Second")
    gone = @user.notifications.order(:created_at).first

    NotificationDigestJob.perform_now
    gone.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
    assert_equal [ @user.email_address ], ActionMailer::Base.deliveries.last.to
  end

  test "no mail at all when every notification is gone" do
    Chats::Message.create!(chat: @chat, user: users(:one), body: "Hello!")

    NotificationDigestJob.perform_now
    @user.notifications.destroy_all

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      perform_enqueued_jobs
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class PurgeNotificationEventsJobTest < ActiveJob::TestCase
  def event_from(days_ago, notify: true)
    event = Noticed::Event.create!(type: "ChatMessageNotifier", params: {})
    event.notifications.create!(recipient: users(:one)) if notify
    event.update_column(:created_at, days_ago.days.ago)
    event
  end

  test "an event nobody is notified about any more is removed" do
    event_from(2, notify: false)

    assert_difference -> { Noticed::Event.count }, -1 do
      PurgeNotificationEventsJob.perform_now
    end
  end

  test "an event people still have notifications for stays" do
    event_from(2)

    assert_no_difference -> { Noticed::Event.count } do
      PurgeNotificationEventsJob.perform_now
    end
  end

  test "a delivery that may still be running is left alone" do
    event_from(0, notify: false)

    assert_no_difference -> { Noticed::Event.count } do
      PurgeNotificationEventsJob.perform_now
    end
  end
end

# frozen_string_literal: true

# Clearing or pruning notifications deletes the rows people see, but every one of them
# points at an event row that stays behind. An event nobody has a notification for any
# more is of no use to anyone, so it goes. Only events old enough that their
# notifications are certainly written, to leave a delivery in progress alone.
class PurgeNotificationEventsJob < ApplicationJob
  queue_as :default

  SETTLE = 1.day

  def perform
    Noticed::Event.where.missing(:notifications).where(created_at: ...SETTLE.ago).delete_all
  end
end

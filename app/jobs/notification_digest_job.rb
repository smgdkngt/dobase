# frozen_string_literal: true

class NotificationDigestJob < ApplicationJob
  queue_as :default

  def perform
    User.where.not(notification_digest: "off").find_each do |user|
      next unless digest_due?(user)

      notifications = unread_notifications_since(user)
      next if notifications.empty?

      NotificationDigestMailer.digest(user, notifications.map(&:id)).deliver_later
      user.update_column(:last_notification_digest_at, Time.current)
    end
  end

  private

  def digest_due?(user)
    return true if user.last_notification_digest_at.nil?

    user.last_notification_digest_at + user.digest_interval <= Time.current
  end

  def unread_notifications_since(user)
    scope = user.notifications.where(read_at: nil)
    scope = scope.where("created_at > ?", user.last_notification_digest_at) if user.last_notification_digest_at
    scope.order(created_at: :desc).to_a
  end
end

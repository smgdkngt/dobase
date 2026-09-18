# frozen_string_literal: true

class NotificationDigestMailer < ApplicationMailer
  # Takes ids, not records: a notification can be read away, cleared or pruned
  # between enqueueing and delivery, and a deleted record would otherwise fail
  # the job's argument deserialization and send nothing at all.
  def digest(user, notification_ids)
    @user = user
    @notifications = user.notifications.where(id: notification_ids).includes(:event).newest_first.to_a
    return if @notifications.empty?

    mail(
      to: @user.email_address,
      subject: "#{@notifications.size} new #{"notification".pluralize(@notifications.size)} from #{Rails.application.config.x.app.name}"
    )
  end
end

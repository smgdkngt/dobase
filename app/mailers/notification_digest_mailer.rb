# frozen_string_literal: true

class NotificationDigestMailer < ApplicationMailer
  # Takes ids, not records: a notification can be read away, cleared or pruned
  # between enqueueing and delivery, and a deleted record would otherwise fail
  # the job's argument deserialization and send nothing at all.
  def digest(user, notification_ids)
    @user = user
    @notifications = user.notifications.where(id: notification_ids).includes(:event).newest_first.to_a
    return if @notifications.empty?

    in_language_of(user) do
      mail(
        to: @user.email_address,
        subject: n_("%{count} new notification from %{app_name}", "%{count} new notifications from %{app_name}",
          @notifications.size, app_name: Rails.application.config.x.app.name)
      )
    end
  end
end

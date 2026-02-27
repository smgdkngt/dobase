# frozen_string_literal: true

class NotificationReadsController < ApplicationController
  def create
    current_user.notifications.unread.mark_as_read

    head :ok
  end
end

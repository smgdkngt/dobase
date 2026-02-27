# frozen_string_literal: true

class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications
      .includes(:event)
      .newest_first
      .limit(20)

    render layout: false
  end
end

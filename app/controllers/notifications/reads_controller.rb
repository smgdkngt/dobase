# frozen_string_literal: true

module Notifications
  class ReadsController < ApplicationController
    def create
      notification = current_user.notifications.find(params[:notification_id])
      notification.mark_as_read!

      head :ok
    end
  end
end

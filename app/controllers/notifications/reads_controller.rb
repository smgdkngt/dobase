# frozen_string_literal: true

module Notifications
  class ReadsController < ApplicationController
    allow_access_tokens

    def create
      @notification = current_user.notifications.find(params[:notification_id])
      @notification.mark_as_read!

      respond_to do |format|
        format.any { head :ok }
        format.json { render "notifications/show" }
      end
    end
  end
end

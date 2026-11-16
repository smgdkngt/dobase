# frozen_string_literal: true

class NotificationReadsController < ApplicationController
  allow_access_tokens

  def create
    marked_as_read = current_user.notifications.unread.mark_as_read

    respond_to do |format|
      # From the bell (its frame follows to the list again) or the notifications page
      format.html { redirect_to notifications_path(page: params[:page].presence, filter: params[:filter].presence_in(NotificationsController::FILTERS)) }
      format.json { render json: { marked_as_read: marked_as_read } }
      format.any { head :ok }
    end
  end
end

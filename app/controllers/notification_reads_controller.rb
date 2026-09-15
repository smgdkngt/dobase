# frozen_string_literal: true

class NotificationReadsController < ApplicationController
  allow_access_tokens

  def create
    marked_as_read = current_user.notifications.unread.mark_as_read

    respond_to do |format|
      format.any { head :ok }
      format.json { render json: { marked_as_read: marked_as_read } }
    end
  end
end

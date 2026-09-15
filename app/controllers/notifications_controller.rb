# frozen_string_literal: true

class NotificationsController < ApplicationController
  PER_PAGE = 20
  MAX_PER_PAGE = 100

  allow_access_tokens

  def index
    @notifications = current_user.notifications.includes(:event).newest_first

    respond_to do |format|
      format.html do
        @notifications = @notifications.limit(PER_PAGE)
        render layout: false
      end
      format.json do
        @notifications = @notifications.unread if params[:unread] == "true"
        @notifications = @notifications.limit((Integer(params[:limit], exception: false) || PER_PAGE).clamp(1, MAX_PER_PAGE))
      end
    end
  end
end

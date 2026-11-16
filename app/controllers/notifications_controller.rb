# frozen_string_literal: true

# The bell's list (the "notifications" frame in the menu), the page with everything
# that is kept (GET /notifications in a window of its own), and the JSON API.
class NotificationsController < ApplicationController
  PER_PAGE = 20
  MAX_PER_PAGE = 100
  FILTERS = %w[all unread].freeze

  allow_access_tokens

  def index
    @notifications = current_user.notifications.includes(:event).newest_first

    respond_to do |format|
      format.html do
        if turbo_frame_request?
          # The bell: what you haven't seen first, or only that
          @filter = params[:filter].presence_in(FILTERS) || "all"
          @any_unread = @notifications.unread.exists?
          @notifications = @notifications.unread if @filter == "unread"
          @notifications = @notifications.limit(PER_PAGE)
          render :popover, layout: false
        else
          set_page
        end
      end
      format.json do
        @notifications = @notifications.unread if params[:unread] == "true"
        set_page(limit: (Integer(params[:limit], exception: false) || PER_PAGE).clamp(1, MAX_PER_PAGE))
      end
    end
  end

  private

  # A page of them, by number from 1: the history, as far as it is kept (User::NOTIFICATION_LIMIT)
  def set_page(limit: PER_PAGE)
    @page = [ Integer(params[:page], exception: false) || 1, 1 ].max
    page = @notifications.offset((@page - 1) * limit).limit(limit + 1).to_a
    @has_more = page.size > limit
    @notifications = page.first(limit)
  end
end

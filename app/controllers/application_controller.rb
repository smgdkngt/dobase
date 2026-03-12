# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  # Requires Popover API, CSS Anchor Positioning, and Invoker Commands (commandfor)
  allow_browser versions: { safari: 26.2, chrome: 135, firefox: 144, opera: 117, ie: false }

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  around_action :set_time_zone
  after_action :track_last_visited_path

  private

  def set_time_zone(&block)
    timezone = current_user&.timezone.presence || "UTC"
    Time.use_zone(timezone, &block)
  end

  def record_not_found
    redirect_to root_path, alert: "That item no longer exists."
  end

  def track_last_visited_path
    return unless current_user
    return unless request.get? && response.successful?
    return if request.xhr? || turbo_frame_request?
    return unless request.path.start_with?("/tools")

    current_user.update_column(:last_visited_path, request.path)
  end
end

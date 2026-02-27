# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern

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

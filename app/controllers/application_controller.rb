# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include DemoRestricted

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
    forget_last_visited_path

    if request.format.json?
      render json: { error: "Not found" }, status: :not_found
    elsif turbo_frame_request?
      # A redirect here would answer with a page that has no matching frame, and the
      # frame (a modal, say) would go blank without saying why.
      render partial: "shared/record_not_found", status: :not_found
    else
      redirect_to root_path, alert: "That item no longer exists."
    end
  end

  # The dashboard sends people back to the page they were last on. Once the
  # record behind that page is gone, following it only lands here again — and
  # the two would bounce off each other forever.
  def forget_last_visited_path
    return unless current_user&.last_visited_path == request.path

    current_user.update_column(:last_visited_path, nil)
  end

  def track_last_visited_path
    return unless current_user
    # API clients reading a tool shouldn't clear the user's activity dots.
    return if Current.access_token
    return unless request.get? && response.successful?
    return if request.xhr? || turbo_frame_request?
    return unless request.path.start_with?("/tools")
    return if request.path.match?(%r{/sync\b})
    # Don't treat a file download as a navigational page — otherwise the
    # dashboard would redirect straight back into the download on every visit.
    return if response.headers["Content-Disposition"].to_s.start_with?("attachment")

    current_user.update_column(:last_visited_path, request.path)

    tool_id = request.path.match(%r{/tools/(\d+)})&.[](1)
    if tool_id
      Collaborator.where(user_id: current_user.id, tool_id: tool_id)
                  .update_all(last_seen_at: Time.current)
    end
  end
end

# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    # Redirect to last visited tool path if it's a navigational page the user
    # can still reach. Skip download endpoints — a stale one would otherwise
    # bounce the user straight into a file download on every visit.
    last_path = current_user.last_visited_path
    if last_path&.start_with?("/tools") && !last_path.match?(%r{/download\z})
      tool_id = last_path[/\/tools\/(\d+)/, 1]
      if tool_id && current_user.accessible_tools.exists?(id: tool_id)
        redirect_to last_path and return
      else
        current_user.update_column(:last_visited_path, nil)
      end
    elsif last_path.present?
      current_user.update_column(:last_visited_path, nil)
    end

    # Otherwise redirect to the first available tool
    first_tool = current_user.ungrouped_tools.first ||
      current_user.accessible_tools.first

    if first_tool
      redirect_to tool_path(first_tool) and return
    end

    # No tools — show empty state
  end
end

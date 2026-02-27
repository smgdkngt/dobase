# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    # Redirect to last visited tool path if still accessible
    if current_user.last_visited_path&.start_with?("/tools")
      tool_id = current_user.last_visited_path[/\/tools\/(\d+)/, 1]
      if tool_id && current_user.accessible_tools.exists?(id: tool_id)
        redirect_to current_user.last_visited_path and return
      else
        current_user.update_column(:last_visited_path, nil)
      end
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

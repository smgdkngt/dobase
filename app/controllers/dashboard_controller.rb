# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    # A tile has no "where you were" to go back to: one that ends up here (its tool
    # was deleted, or isn't yours any more) is dealt with by the workspace
    return if tile?

    # A wide window works in the tiling workspace. A phone never does, and neither
    # does a window the workspace itself found too narrow (it says so with ?one).
    return redirect_onwards(workspace_path) if workspace_wanted? && !phone? && params[:one].blank?

    # Redirect to last visited tool path if it's a navigational page the user
    # can still reach. Skip download endpoints — a stale one would otherwise
    # bounce the user straight into a file download on every visit.
    last_path = current_user.last_visited_path
    if User.page_to_return_to?(last_path)
      tool_id = last_path[/\/tools\/(\d+)/, 1]
      if tool_id && current_user.accessible_tools.exists?(id: tool_id)
        return redirect_onwards(last_path)
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
      redirect_onwards(tool_path(first_tool))
    end

    # No tools — show empty state
  end

  private

  # Nobody stays on this page: what was said on the way here (a tool deleted, an
  # invitation declined, a page that isn't yours) is said on the page it sends you on to
  def redirect_onwards(path)
    flash.keep
    redirect_to path
  end
end

# frozen_string_literal: true

# The tiling workspace: no sidebar, every tool you open is a tile, and the tiles
# arrange themselves (workspace_controller.js). Each tile is a tool's own page in a
# frame (ApplicationController#tile?). Which tiles are open is kept by the browser;
# the server draws the room they are in.
class WorkspacesController < ApplicationController
  def show
    # A tile that ends up here is dealt with by the workspace around it: the dashboard
    # is no tool's page
    return redirect_to root_path if tile?

    cookies.delete(:workspace)
    @workspace = true
    @start_path = start_path
  end

  # One tool at a time, with the sidebar, in this browser from now on
  def destroy
    cookies.permanent[:workspace] = { value: "off", same_site: :lax }
    redirect_to root_path, status: :see_other
  end

  private

  # What a workspace with nothing in it yet opens with: the tool you were last on,
  # or your first one
  def start_path
    last = current_user.last_visited_path
    tool_id = last.to_s[%r{\A/tools/(\d+)}, 1]
    return last if tool_id && current_user.accessible_tools.exists?(id: tool_id) && !last.match?(%r{/download\z})

    tool = current_user.ungrouped_tools.first || current_user.accessible_tools.first
    tool_path(tool) if tool
  end
end

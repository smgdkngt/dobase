# frozen_string_literal: true

# The tiling workspace: no sidebar, every tool you open is a tile, and the tiles
# arrange themselves (workspace_controller.js). Each tile is a tool's own page in a
# frame (ApplicationController#tile?). Which tiles are open and where is the
# browser's to decide and kept here per person (WorkspaceLayout), so it is the same
# in every browser; the server draws the room they are in.
class WorkspacesController < ApplicationController
  def show
    # A tile that ends up here is dealt with by the workspace around it: the dashboard
    # is no tool's page
    return redirect_to root_path if tile? && request.format.html?

    @layout = current_user.workspace_layout || current_user.build_workspace_layout
    @workspace = true
    @start_path = start_path

    respond_to do |format|
      format.html
      format.json
    end
  end

  # A browser changed the arrangement: kept when it was made from the one kept here,
  # and otherwise the browser gets that one back to go on with (409)
  def update
    @layout = WorkspaceLayout.create_or_find_by!(user: current_user)
    kept = @layout.keep(arrangement, from: params[:revision].to_i, by: params[:client].to_s.first(64).presence)

    render :show, status: kept ? :ok : :conflict, formats: :json
  rescue ActiveRecord::RecordInvalid => invalid
    render json: { errors: invalid.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def arrangement
    state = params[:state]
    state.respond_to?(:to_unsafe_h) ? state.to_unsafe_h : {}
  end

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

# frozen_string_literal: true

# The tiling workspace: no sidebar, every tool you open is a tile, and the tiles
# arrange themselves (workspace_controller.js). Each tile is a tool's own page in a
# frame, the same way a tool beside another one is (ApplicationController#side_pane?).
# Which tiles are open is kept by the browser, and so is working this way at all: a
# cookie, so a phone signed in to the same account stays as it is.
class WorkspacesController < ApplicationController
  def show
    # A tile that ends up here closes itself: the dashboard is no tool's page
    return redirect_to root_path if side_pane?

    cookies.permanent[:workspace] = { value: "on", same_site: :lax }
    @workspace = true
  end

  # Back to one tool at a time, with the sidebar
  def destroy
    cookies.delete(:workspace)
    redirect_to root_path, status: :see_other
  end
end

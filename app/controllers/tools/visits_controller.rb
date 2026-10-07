# frozen_string_literal: true

module Tools
  # "I have seen this tool as it is now." Opening a tool's page says so by itself
  # (ApplicationController#track_last_visited_path). In the workspace a tool stays
  # open as a tile for hours and what is new arrives in it live, without a page being
  # opened; the workspace says it for the tiles that are in sight
  # (workspace_controller.js), so the dot for what is new doesn't come back.
  class VisitsController < ApplicationController
    include ToolScoped
    announces_no_change :create

    def create
      @tool.collaborators.where(user: current_user).update_all(last_seen_at: Time.current)
      head :no_content
    end
  end
end

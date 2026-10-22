# frozen_string_literal: true

module Profiles
  # Whether programs may connect by MCP at all. Switching it off ends every
  # connection there is (User#end_connections).
  class McpAccessesController < ApplicationController
    def update
      current_user.update!(mcp_enabled: params[:enabled] == "true")
      redirect_to edit_profile_path(tab: "api"), status: :see_other
    end
  end
end

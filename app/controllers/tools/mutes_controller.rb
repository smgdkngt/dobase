# frozen_string_literal: true

module Tools
  # Per-tool notification muting for the current user. Mute and unmute are
  # actions on the current_user's own collaborator record — owners can't
  # silence other people, only themselves.
  class MutesController < ApplicationController
    include ToolScoped
    before_action :set_collaborator

    def create
      @collaborator.mute!
      redirect_back_or_to edit_tool_path(@tool), notice: "Notifications muted for #{@tool.name}."
    end

    def destroy
      @collaborator.unmute!
      redirect_back_or_to edit_tool_path(@tool), notice: "Notifications unmuted for #{@tool.name}."
    end

    private

      def set_collaborator
        @collaborator = @tool.collaborators.find_by!(user: current_user)
      end
  end
end

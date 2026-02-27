# frozen_string_literal: true

module SidebarGroups
  class PositionsController < ApplicationController
    before_action :set_sidebar_group

    def update
      tool_ids = params[:tool_ids] || []
      tool_ids.each_with_index do |tid, idx|
        @group.memberships.where(tool_id: tid).update_all(position: idx)
      end
      render json: { success: true }
    end

    private

    def set_sidebar_group
      @group = current_user.sidebar_groups.find(params[:sidebar_group_id])
    end
  end
end

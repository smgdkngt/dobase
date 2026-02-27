# frozen_string_literal: true

module SidebarGroups
  class MembershipsController < ApplicationController
    before_action :set_sidebar_group

    def create
      tool = current_user.accessible_tools.find(params[:tool_id])

      # Remove from any existing group for this user first
      Sidebar::Membership.joins(:group)
        .where(sidebar_groups: { user_id: current_user.id }, tool_id: tool.id)
        .destroy_all

      max_pos = @group.memberships.maximum(:position) || -1
      membership = @group.memberships.build(tool: tool, position: max_pos + 1)

      if membership.save
        respond_to do |format|
          format.html { redirect_back fallback_location: root_path }
          format.json { render json: { success: true }, status: :created }
        end
      else
        respond_to do |format|
          format.html { redirect_back fallback_location: root_path, alert: membership.errors.full_messages.join(", ") }
          format.json { render json: { errors: membership.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @group.memberships.where(tool_id: params[:id]).destroy_all
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path }
        format.json { render json: { success: true } }
      end
    end

    private

    def set_sidebar_group
      @group = current_user.sidebar_groups.find(params[:sidebar_group_id])
    end
  end
end

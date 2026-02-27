# frozen_string_literal: true

class SidebarPositionsController < ApplicationController
  def update
    if params[:group_ids]
      reorder_groups
    elsif params[:tool_ids]
      reorder_ungrouped_tools
    else
      render json: { error: "Missing parameters" }, status: :unprocessable_entity
    end
  end

  private

  def reorder_groups
    params[:group_ids].each_with_index do |gid, idx|
      current_user.sidebar_groups.where(id: gid).update_all(position: idx)
    end
    render json: { success: true }
  end

  def reorder_ungrouped_tools
    params[:tool_ids].each_with_index do |tid, idx|
      current_user.accessible_tools.where(id: tid).update_all(sidebar_position: idx)
    end
    render json: { success: true }
  end
end

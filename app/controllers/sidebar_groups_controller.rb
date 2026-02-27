# frozen_string_literal: true

class SidebarGroupsController < ApplicationController
  before_action :set_sidebar_group, only: [ :update, :destroy ]

  def create
    max_pos = current_user.sidebar_groups.maximum(:position) || -1
    @group = current_user.sidebar_groups.build(
      name: params[:name] || "New Group",
      position: max_pos + 1
    )

    if @group.save
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path }
        format.json { render json: { id: @group.id, name: @group.name, position: @group.position }, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: @group.errors.full_messages.join(", ") }
        format.json { render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @group.update(group_params)
      render json: { id: @group.id, name: @group.name, collapsed: @group.collapsed }
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path }
      format.json { render json: { success: true } }
    end
  end

  private

  def set_sidebar_group
    @group = current_user.sidebar_groups.find(params[:id])
  end

  def group_params
    params.permit(:name, :collapsed)
  end
end

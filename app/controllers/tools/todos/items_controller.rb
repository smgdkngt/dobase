# frozen_string_literal: true

module Tools
  module Todos
    class ItemsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_item

      def show
        @collaborators = @tool.users
        render layout: false
      end

      def update
        previous_assigned_user_id = @item.assigned_user_id
        if @item.update(item_params)
          notify_assignment(previous_assigned_user_id)
          respond_to do |format|
            format.html do
              if request.headers["Turbo-Frame"] == "item-detail-content"
                redirect_to tool_todo_item_path(@tool, @item)
              else
                redirect_to tool_todo_path(@tool)
              end
            end
            format.json { render json: { success: true } }
          end
        else
          respond_to do |format|
            format.html do
              @collaborators = @tool.users
              render :show, layout: false, status: :unprocessable_entity
            end
            format.json { render json: { errors: @item.errors }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        if @item.destroy
          respond_to do |format|
            format.html { redirect_to tool_todo_path(@tool) }
            format.json { render json: { success: true } }
          end
        else
          respond_to do |format|
            format.html { redirect_to tool_todo_path(@tool), alert: "Could not delete item" }
            format.json { render json: { error: "Could not delete item" }, status: :unprocessable_entity }
          end
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_item
        @item = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }).find(params[:id])
      end

      def item_params
        params.require(:item).permit(:title, :description, :due_date, :assigned_user_id)
      end

      def notify_assignment(previous_assigned_user_id)
        return unless @item.assigned_user_id.present?
        return if @item.assigned_user_id == previous_assigned_user_id
        return if @item.assigned_user_id == current_user.id

        assignee = User.find(@item.assigned_user_id)
        TodoAssignmentNotifier.with(item: @item, assigner: current_user, tool: @tool).deliver(assignee)
        assignee.prune_notifications!
      end
    end
  end
end

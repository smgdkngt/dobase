# frozen_string_literal: true

module Tools
  module Todos
    class ItemsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_item

      def show
        respond_to do |format|
          format.html do
            @collaborators = @tool.users
            render layout: false
          end
          format.json
        end
      end

      def update
        if @item.update(item_params.merge(updated_by: current_user))
          @item.notify_assignee(current_user) if @item.assigned_user_id_previously_changed?
          respond_to do |format|
            format.html do
              if request.headers["Turbo-Frame"] == "item-detail-content"
                redirect_to tool_todo_item_path(@tool, @item)
              else
                redirect_to tool_todo_path(@tool)
              end
            end
            format.json { render :show }
          end
        else
          respond_to do |format|
            format.html do
              @collaborators = @tool.users
              render :show, layout: false, status: :unprocessable_entity
            end
            format.json { render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        if @item.destroy
          respond_to do |format|
            format.html { redirect_to tool_todo_path(@tool) }
            format.json { head :no_content }
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
        params.require(:item).permit(:title, :description, :due_date, :assigned_user_id, :recurrence_rule)
      end
    end
  end
end

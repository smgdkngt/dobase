# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class CompletionsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_item

        # POST /tools/:tool_id/todo/items/:item_id/completion
        def create
          @item.update!(completed_at: Time.current)
          notify_completion
          respond_to do |format|
            format.html { redirect_to tool_todo_path(@tool) }
            format.json { render json: { success: true, completed_at: @item.completed_at } }
          end
        end

        # DELETE /tools/:tool_id/todo/items/:item_id/completion
        def destroy
          @item.update!(completed_at: nil)
          respond_to do |format|
            format.html { redirect_to tool_todo_path(@tool) }
            format.json { render json: { success: true } }
          end
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_item
          @item = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }).find(params[:item_id])
        end

        def notify_completion
          return unless @item.assigned_user_id.present?
          return if @item.assigned_user_id == current_user.id

          assignee = User.find(@item.assigned_user_id)
          return if @tool.muted_by?(assignee)

          TodoCompletedNotifier.with(item: @item, completer: current_user, tool: @tool).deliver(assignee)
          assignee.prune_notifications!
        end
      end
    end
  end
end

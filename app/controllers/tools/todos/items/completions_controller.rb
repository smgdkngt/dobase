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
      end
    end
  end
end

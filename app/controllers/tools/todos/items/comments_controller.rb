# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class CommentsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_item
        before_action :set_comment, only: :destroy

        def create
          @item.comments.create!(user: current_user, body: params[:body])
          redirect_to tool_todo_item_path(@tool, @item)
        end

        def destroy
          unless @comment.user_id == current_user.id || @tool.owned_by?(current_user)
            head :forbidden and return
          end

          @comment.destroy!
          redirect_to tool_todo_item_path(@tool, @item)
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_item
          @item = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }).find(params[:item_id])
        end

        def set_comment
          @comment = @item.comments.find(params[:id])
        end
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class CommentsController < ApplicationController
        include ToolScoped

        allow_access_tokens
        before_action :set_item
        before_action :set_comment, only: :destroy

        def create
          @comment = @item.comments.new(user: current_user, body: params[:body])

          respond_to do |format|
            if @comment.save
              format.html { redirect_to tool_todo_item_path(@tool, @item) }
              format.json { render :show, status: :created }
            else
              format.html { redirect_to tool_todo_item_path(@tool, @item) }
              format.json { render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity }
            end
          end
        end

        def destroy
          unless @comment.user_id == current_user.id || @tool.owned_by?(current_user)
            head :forbidden and return
          end

          @comment.destroy!

          respond_to do |format|
            format.html { redirect_to tool_todo_item_path(@tool, @item) }
            format.json { head :no_content }
          end
        end

        private

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

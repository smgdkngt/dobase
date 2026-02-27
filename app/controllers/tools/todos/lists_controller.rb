# frozen_string_literal: true

module Tools
  module Todos
    class ListsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_list, only: %i[update destroy]

      def create
        position = @tool.todo_lists.maximum(:position).to_i + 1
        @list = @tool.todo_lists.create!(title: params[:title] || "New List", position: position)
        respond_to do |format|
          format.html { redirect_to tool_todo_path(@tool) }
          format.json { render json: { id: @list.id, title: @list.title } }
        end
      end

      def update
        @list.update!(list_params)
        render json: { id: @list.id, title: @list.title }
      end

      def destroy
        @list.destroy!
        redirect_to tool_todo_path(@tool)
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_list
        @list = @tool.todo_lists.find(params[:id])
      end

      def list_params
        params.permit(:title, :description)
      end
    end
  end
end

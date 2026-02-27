# frozen_string_literal: true

module Tools
  module Todos
    class PositionsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def update
        params[:list_ids].each_with_index do |id, index|
          @tool.todo_lists.where(id: id).update_all(position: index)
        end
        render json: { success: true }
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

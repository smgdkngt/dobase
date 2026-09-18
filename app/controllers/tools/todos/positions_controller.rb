# frozen_string_literal: true

module Tools
  module Todos
    class PositionsController < ApplicationController
      include ToolScoped

      def update
        params[:list_ids].each_with_index do |id, index|
          @tool.todo_lists.where(id: id).update_all(position: index)
        end
        render json: { success: true }
      end
    end
  end
end

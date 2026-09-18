# frozen_string_literal: true

module Tools
  module Boards
    class PositionsController < ApplicationController
      include ToolScoped

      def update
        params[:column_ids].each_with_index do |id, index|
          @tool.board.columns.where(id: id).update_all(position: index)
        end
        render json: { success: true }
      end
    end
  end
end

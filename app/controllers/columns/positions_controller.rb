# frozen_string_literal: true

module Columns
  class PositionsController < ApplicationController
    include ToolAuthorization

    before_action :set_column
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def update
      params[:card_ids].each_with_index do |id, index|
        Boards::Card.where(id: id).update_all(column_id: @column.id, position: index)
      end
      render json: { success: true }
    end

    private

    def set_column
      @column = Boards::Column.find(params[:column_id])
    end

    def set_tool
      @tool = @column.board.tool
    end
  end
end

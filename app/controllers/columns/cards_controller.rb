# frozen_string_literal: true

module Columns
  class CardsController < ApplicationController
    include ToolAuthorization

    before_action :set_column
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def create
      position = @column.cards.maximum(:position).to_i + 1
      @column.cards.create!(title: params[:title], position: position)
      redirect_to tool_board_path(@tool)
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

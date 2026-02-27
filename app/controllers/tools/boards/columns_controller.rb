# frozen_string_literal: true

module Tools
  module Boards
    class ColumnsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_board
      before_action :set_column, only: %i[update destroy]

      def create
        position = @board.columns.maximum(:position).to_i + 1
        @column = @board.columns.create!(name: params[:name] || "New Column", position: position)
        respond_to do |format|
          format.html { redirect_to tool_board_path(@tool) }
          format.json { render json: { id: @column.id, name: @column.name } }
        end
      end

      def update
        if params.key?(:collapsed)
          @column.update!(collapsed: params[:collapsed])
          head :ok
        else
          @column.update!(name: params[:name])
          render json: { id: @column.id, name: @column.name }
        end
      end

      def destroy
        @column.destroy!
        redirect_to tool_board_path(@tool)
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_board
        @board = @tool.board
      end

      def set_column
        @column = @board.columns.find(params[:id])
      end
    end
  end
end

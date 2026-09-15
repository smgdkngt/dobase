# frozen_string_literal: true

module Tools
  module Boards
    class ColumnsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_board
      before_action :set_column, only: %i[update destroy]

      def create
        position = @board.columns.maximum(:position).to_i + 1
        @column = @board.columns.new(name: params[:name] || "New Column", position: position, created_by: current_user, updated_by: current_user)

        respond_to do |format|
          if @column.save
            format.html { redirect_to tool_board_path(@tool) }
            format.json { render :show, status: :created }
          else
            format.html { redirect_to tool_board_path(@tool), alert: @column.errors.full_messages.to_sentence }
            format.json { render json: { errors: @column.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def update
        if params.key?(:collapsed)
          @column.update!(collapsed: params[:collapsed], updated_by: current_user)
          head :ok
        elsif @column.update(name: params[:name], updated_by: current_user)
          render :show, formats: :json
        else
          render json: { errors: @column.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @column.destroy!

        respond_to do |format|
          format.html { redirect_to tool_board_path(@tool) }
          format.json { head :no_content }
        end
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

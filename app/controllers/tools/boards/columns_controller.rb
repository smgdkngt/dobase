# frozen_string_literal: true

module Tools
  module Boards
    class ColumnsController < ApplicationController
      include ToolScoped

      allow_access_tokens
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
          # Collapsing is personal, so it records the viewer and leaves the
          # column itself — and everyone else's board — alone.
          if ActiveModel::Type::Boolean.new.cast(params[:collapsed])
            @column.collapse_for(current_user)
          else
            @column.expand_for(current_user)
          end
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

      def set_board
        @board = @tool.board
      end

      def set_column
        @column = @board.columns.find(params[:id])
      end
    end
  end
end

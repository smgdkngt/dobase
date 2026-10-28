# frozen_string_literal: true

module Columns
  class CardsController < ApplicationController
    include ToolAuthorization
    include TakesDropped

    allow_access_tokens

    before_action :set_column
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def create
      position = @column.cards.maximum(:position).to_i + 1
      @card = @column.cards.new((dropped ? {} : card_params).merge(position: position, created_by: current_user, updated_by: current_user))
      @card.take(dropped, base_url: request.base_url) if dropped

      respond_to do |format|
        if @card.save
          @card.notify_assignee(current_user)
          format.html { redirect_to tool_board_path(@tool) }
          format.json { render "tools/boards/cards/show", status: :created }
        else
          format.html { redirect_to tool_board_path(@tool), alert: @card.errors.full_messages.to_sentence }
          format.json { render json: { errors: @card.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_column
      @column = Boards::Column.find(params[:column_id])
    end

    def set_tool
      @tool = @column.board.tool
    end

    def card_params
      params.require(:card).permit(:title, :description, :color, :due_date, :assigned_user_id)
    end
  end
end

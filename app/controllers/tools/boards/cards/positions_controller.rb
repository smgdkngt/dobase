# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class PositionsController < ApplicationController
        include ToolScoped

        allow_access_tokens
        # A JSON body without "position" would otherwise be wrapped under params[:position].
        wrap_parameters false
        before_action :set_card

        # PATCH /tools/:tool_id/board/cards/:card_id/position
        # Moves a card to column_id (defaults to its own) at position (defaults to the bottom).
        def update
          column = params[:column_id].present? ? @tool.board.columns.find(params[:column_id]) : @card.column
          previous_column = @card.column

          @card.move_to(column, position: params[:position], by: current_user)
          notify_card_moved if column != previous_column

          respond_to do |format|
            format.html { redirect_to tool_board_path(@tool) }
            format.json { render "tools/boards/cards/show" }
          end
        end

        private

        def set_card
          @card = @tool.board.cards.find(params[:card_id])
        end

        def notify_card_moved
          assignee = @card.assigned_user
          return if assignee.nil? || assignee == current_user
          return if @tool.muted_by?(assignee) || !@tool.accessible_by?(assignee)

          CardMovedNotifier.with(card: @card, mover: current_user, tool: @tool, column: @card.column).deliver(assignee)
          assignee.prune_notifications!
        end
      end
    end
  end
end

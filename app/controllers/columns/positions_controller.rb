# frozen_string_literal: true

module Columns
  class PositionsController < ApplicationController
    include ToolAuthorization

    before_action :set_column
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def update
      card_ids = board_card_ids
      # Find cards that are moving TO this column from a different one
      moved_cards = Boards::Card.where(id: card_ids).where.not(column_id: @column.id).to_a

      column_order(card_ids).each_with_index do |id, index|
        Boards::Card.where(id: id).update_all(column_id: @column.id, position: index)
      end

      notify_card_moves(moved_cards)
      render json: { success: true }
    end

    private

    def set_column
      @column = Boards::Column.find(params[:column_id])
    end

    def set_tool
      @tool = @column.board.tool
    end

    # The requested card ids, in order, limited to cards already on this board.
    # Ids of cards on other boards are dropped rather than moved over.
    def board_card_ids
      requested = Array(params[:card_ids]).map(&:to_i)
      requested & @column.board.cards.where(id: requested).ids
    end

    # With the assignee filter on, the request only lists the cards that were shown.
    # The column's other cards keep their places: each stays after the card it followed.
    def column_order(requested)
      current = @column.cards.order(:position, :id).ids
      KeepHiddenInPlace.call(current, requested)
    end

    def notify_card_moves(moved_cards)
      moved_cards.each do |card|
        next unless card.assigned_user_id.present?
        next if card.assigned_user_id == current_user.id

        assignee = User.find_by(id: card.assigned_user_id)
        next if assignee.nil? || !@tool.accessible_by?(assignee) || @tool.muted_by?(assignee)

        CardMovedNotifier.with(card: card, mover: current_user, tool: @tool, column: @column).deliver(assignee)
        assignee.prune_notifications!
      end
    end
  end
end

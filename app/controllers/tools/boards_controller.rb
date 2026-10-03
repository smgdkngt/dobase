# frozen_string_literal: true

module Tools
  class BoardsController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      @board = @tool.board
      return if float_card

      @columns = @board.columns.includes(cards: [ { assigned_user: { avatar_attachment: :blob } }, :comments, :attachments, :rich_text_description ]).order(:position)
      @collapsed_column_ids = ::Boards::Column.collapsed_ids_for(current_user, @columns)
      @collaborators = @tool.users
      @assignee_filter = params[:assignee]
    end

    private

    # Floating over the workspace (floating?): the card the address names, and nothing
    # of the board. A card that is gone gets the board, which says so.
    def float_card
      return unless floating? && (@card = @board.cards.find_by(id: params[:card]))

      @collaborators = @tool.users
      current_user.read_notifications_about!(records: [ @card ], urls: [ tool_board_path(@tool, card: @card.id) ])
      render :floating
    end
  end
end

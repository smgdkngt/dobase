# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class ArchivesController < ApplicationController
        include ToolScoped

        allow_access_tokens
        before_action :set_card

        # POST /tools/:tool_id/board/cards/:card_id/archive
        def create
          @card.update!(archived_at: Time.current)
          respond_with_card
        end

        # DELETE /tools/:tool_id/board/cards/:card_id/archive
        def destroy
          @card.update!(archived_at: nil)
          respond_with_card
        end

        private

        def set_card
          @card = @tool.board.cards.find(params[:card_id])
        end

        def respond_with_card
          respond_to do |format|
            format.html { redirect_to tool_board_path(@tool) }
            format.json { render "tools/boards/cards/show" }
          end
        end
      end
    end
  end
end

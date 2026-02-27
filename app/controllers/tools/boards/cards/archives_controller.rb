# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class ArchivesController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_card

        # POST /tools/:tool_id/board/cards/:card_id/archive
        def create
          @card.update!(archived_at: Time.current)
          redirect_to tool_board_path(@tool)
        end

        # DELETE /tools/:tool_id/board/cards/:card_id/archive
        def destroy
          @card.update!(archived_at: nil)
          redirect_to tool_board_path(@tool)
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_card
          @card = @tool.board.cards.find(params[:card_id])
        end
      end
    end
  end
end

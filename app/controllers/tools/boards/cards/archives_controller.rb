# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class ArchivesController < ApplicationController
        include ToolAuthorization

        allow_access_tokens

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
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

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

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

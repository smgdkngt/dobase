# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class CommentsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_card
        before_action :set_comment, only: :destroy

        def create
          @card.comments.create!(user: current_user, body: params[:body])
          redirect_to tool_board_card_path(@tool, @card)
        end

        def destroy
          unless @comment.user_id == current_user.id || @tool.owned_by?(current_user)
            head :forbidden and return
          end

          @comment.destroy!
          redirect_to tool_board_card_path(@tool, @card)
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_card
          @card = @tool.board.cards.find(params[:card_id])
        end

        def set_comment
          @comment = @card.comments.find(params[:id])
        end
      end
    end
  end
end

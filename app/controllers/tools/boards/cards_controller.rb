# frozen_string_literal: true

module Tools
  module Boards
    class CardsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_card

      def show
        respond_to do |format|
          format.html do
            @collaborators = @tool.users
            render layout: false
          end
          format.json
        end
      end

      def update
        if @card.update(card_params.merge(updated_by: current_user))
          @card.notify_assignee(current_user) if @card.assigned_user_id_previously_changed?
          respond_to do |format|
            format.html do
              if request.headers["Turbo-Frame"] == "card-detail-content"
                redirect_to tool_board_card_path(@tool, @card)
              else
                redirect_to tool_board_path(@tool)
              end
            end
            format.json { render :show }
          end
        else
          respond_to do |format|
            format.html do
              @collaborators = @tool.users
              render :show, layout: false, status: :unprocessable_entity
            end
            format.json { render json: { errors: @card.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        if @card.destroy
          respond_to do |format|
            format.html { redirect_to tool_board_path(@tool) }
            format.json { head :no_content }
          end
        else
          respond_to do |format|
            format.html { redirect_to tool_board_path(@tool), alert: "Could not delete card" }
            format.json { render json: { error: "Could not delete card" }, status: :unprocessable_entity }
          end
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_card
        @card = @tool.board.cards.find(params[:id])
      end

      def card_params
        params.require(:card).permit(:title, :description, :color, :due_date, :assigned_user_id)
      end
    end
  end
end

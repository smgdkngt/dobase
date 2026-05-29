# frozen_string_literal: true

module Tools
  module Boards
    class CardsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_card

      def show
        @collaborators = @tool.users
        render layout: false
      end

      def update
        previous_assigned_user_id = @card.assigned_user_id
        if @card.update(card_params.merge(updated_by: current_user))
          notify_assignment(previous_assigned_user_id)
          respond_to do |format|
            format.html do
              if request.headers["Turbo-Frame"] == "card-detail-content"
                redirect_to tool_board_card_path(@tool, @card)
              else
                redirect_to tool_board_path(@tool)
              end
            end
            format.json { render json: { success: true } }
          end
        else
          respond_to do |format|
            format.html do
              @collaborators = @tool.users
              render :show, layout: false, status: :unprocessable_entity
            end
            format.json { render json: { errors: @card.errors }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        if @card.destroy
          respond_to do |format|
            format.html { redirect_to tool_board_path(@tool) }
            format.json { render json: { success: true } }
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

      def notify_assignment(previous_assigned_user_id)
        return unless @card.assigned_user_id.present?
        return if @card.assigned_user_id == previous_assigned_user_id
        return if @card.assigned_user_id == current_user.id

        assignee = User.find(@card.assigned_user_id)
        return if @tool.muted_by?(assignee)

        CardAssignmentNotifier.with(card: @card, assigner: current_user, tool: @tool).deliver(assignee)
        assignee.prune_notifications!
      end

      def notify_card_moved
        return unless @card.column_id_previously_changed?
        return unless @card.assigned_user_id.present?
        return if @card.assigned_user_id == current_user.id

        assignee = User.find(@card.assigned_user_id)
        return if @tool.muted_by?(assignee)

        CardMovedNotifier.with(card: @card, mover: current_user, tool: @tool, column: @card.column).deliver(assignee)
        assignee.prune_notifications!
      end
    end
  end
end

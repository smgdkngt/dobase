# frozen_string_literal: true

module Tools
  module Rooms
    # Broadcasts a lightweight, non-persisted presence signal so a collaborator's
    # sidebar shows an in-call indicator for this tool while someone else is on a
    # call. Deliberately separate from the Noticed notification system — this
    # isn't a notification (nothing to read, no bell, no email), just a live
    # "someone is here" ping. See NotificationChannel / notifications_controller.js,
    # which special-cases the `type: "room_activity"` payload.
    class ActivitiesController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      # POST /tools/:tool_id/room/activity — the current user joined the call
      def create
        broadcast_activity(active: true)
        head :no_content
      end

      # DELETE /tools/:tool_id/room/activity — the current user left the call.
      # The client says how many participants it left behind, so the indicator
      # only clears when the call is actually empty.
      def destroy
        broadcast_activity(active: params[:remaining].to_i.positive?)
        head :no_content
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def broadcast_activity(active:)
        @tool.notifiable_users.where.not(id: current_user.id).find_each do |user|
          ActionCable.server.broadcast("notifications:#{user.id}", {
            type: "room_activity",
            tool_id: @tool.id,
            active: active
          })
        end
      end
    end
  end
end

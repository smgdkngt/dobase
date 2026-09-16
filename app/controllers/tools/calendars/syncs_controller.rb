# frozen_string_literal: true

module Tools
  module Calendars
    class SyncsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def create
        unless @tool.calendar_account
          if request.format.json?
            render json: { error: "Calendar account not configured" }, status: :not_found
          else
            redirect_to new_tool_calendar_account_path(@tool), alert: "Please configure your calendar account first."
          end
          return
        end

        @tool.calendar_account.mark_syncing!
        SyncCalendarsJob.perform_later(@tool.calendar_account.id, discover: true)

        respond_to do |format|
          format.turbo_stream { head :ok }
          format.html { redirect_to tool_calendar_path(@tool), status: :see_other }
          format.json { render json: sync_status, status: :created }
        end
      end

      def show
        # Status endpoint for polling
        render json: sync_status
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def sync_status
        {
          status: @tool.calendar_account&.sync_status,
          last_synced_at: @tool.calendar_account&.last_synced_at&.iso8601
        }
      end
    end
  end
end

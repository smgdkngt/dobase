# frozen_string_literal: true

module Tools
  module Mails
    class SyncsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      # POST /tools/:tool_id/sync
      def create
        unless @tool.mail_account
          respond_to do |format|
            format.html { redirect_to new_tool_mails_account_path(@tool), alert: "Please configure your mail account first." }
            format.json { render json: { error: "Mail account not configured" }, status: :not_found }
          end
          return
        end

        @tool.mail_account.mark_syncing!
        SyncEmailsJob.perform_later(@tool.mail_account.id)

        respond_to do |format|
          format.turbo_stream { head :ok }
          format.html { redirect_to tool_mails_path(@tool), status: :see_other }
          format.json { render json: sync_status }
        end
      end

      # GET /tools/:tool_id/sync
      def show
        render json: sync_status
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def sync_status
        {
          status: @tool.mail_account&.sync_status,
          last_synced_at: @tool.mail_account&.last_synced_at&.iso8601
        }
      end
    end
  end
end

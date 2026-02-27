# frozen_string_literal: true

module Tools
  module Mails
    class SyncsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      # POST /tools/:tool_id/mails/sync
      def create
        unless @tool.mail_account
          redirect_to new_tool_mails_account_path(@tool), alert: "Please configure your mail account first."
          return
        end

        @tool.mail_account.mark_syncing!
        SyncEmailsJob.perform_later(@tool.mail_account.id)

        respond_to do |format|
          format.turbo_stream { head :ok }
          format.html { redirect_to tool_mails_path(@tool), status: :see_other }
        end
      end

      # GET /tools/:tool_id/mails/sync
      def show
        render json: {
          status: @tool.mail_account&.sync_status,
          last_synced_at: @tool.mail_account&.last_synced_at&.iso8601
        }
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

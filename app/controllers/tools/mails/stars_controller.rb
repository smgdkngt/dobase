# frozen_string_literal: true

module Tools
  module Mails
    class StarsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/star
      def create
        @message.update!(starred: true)
        sync_starred(true)
        redirect_back fallback_location: tool_mails_path(@tool)
      end

      # DELETE /tools/:tool_id/mails/:mail_id/star
      def destroy
        @message.update!(starred: false)
        sync_starred(false)
        redirect_back fallback_location: tool_mails_path(@tool)
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.mail_account.messages.find(params[:mail_id])
      end

      def sync_starred(starred)
        return unless @message.uid.present?
        ImapSyncJob.perform_later(@tool.mail_account.id, "set_starred", @message.uid, @message.folder || "INBOX", starred)
      end
    end
  end
end

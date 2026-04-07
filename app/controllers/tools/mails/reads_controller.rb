# frozen_string_literal: true

module Tools
  module Mails
    class ReadsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/read
      def create
        @message.mark_as_read!
        sync_imap(:mark_as_read)
        redirect_back fallback_location: tool_mails_path(@tool)
      end

      # DELETE /tools/:tool_id/mails/:mail_id/read
      def destroy
        @message.mark_as_unread!
        sync_imap(:mark_as_unread)
        redirect_back fallback_location: tool_mails_path(@tool)
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.mail_account.messages.find(params[:mail_id])
      end

      def sync_imap(action)
        return unless @message.uid.present?
        ImapSyncJob.perform_later(@tool.mail_account.id, action.to_s, @message.uid, @message.folder || "INBOX")
      end
    end
  end
end

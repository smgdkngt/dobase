# frozen_string_literal: true

module Tools
  module Mails
    class StarsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/star
      def create
        @message.update!(starred: true)
        sync_starred(true)
        respond_with_message
      end

      # DELETE /tools/:tool_id/mails/:mail_id/star
      def destroy
        @message.update!(starred: false)
        sync_starred(false)
        respond_with_message
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end

      def sync_starred(starred)
        return unless @message.uid.present?
        ImapSyncJob.perform_later(@tool.mail_account.id, "set_starred", @message.uid, @message.folder || "INBOX", starred)
      end

      def respond_with_message
        respond_to do |format|
          format.html { redirect_back fallback_location: tool_mails_path(@tool) }
          format.json { render "tools/mails/message" }
        end
      end
    end
  end
end

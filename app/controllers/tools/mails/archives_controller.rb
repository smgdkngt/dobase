# frozen_string_literal: true

module Tools
  module Mails
    class ArchivesController < ApplicationController
      include ToolAuthorization
      include NextMailNavigation

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/archive
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        @message.update!(archived: true)
        sync_imap(:mark_as_read)
        redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email archived.")
      end

      # DELETE /tools/:tool_id/mails/:mail_id/archive
      def destroy
        next_msg = find_next_message(@message, "archive")
        @message.update!(archived: false)
        sync_imap(:mark_as_unread)
        redirect_to_next_mail_or_fallback(next_msg, folder: "archive", notice: "Email unarchived.")
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

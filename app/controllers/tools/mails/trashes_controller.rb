# frozen_string_literal: true

module Tools
  module Mails
    class TrashesController < ApplicationController
      include ToolAuthorization
      include NextMailNavigation

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message, only: %i[create destroy]

      # POST /tools/:tool_id/mails/:mail_id/trash
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        @message.update!(trashed: true, archived: false)
        sync_delete_to_imap(@message)
        redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email moved to trash.")
      end

      # DELETE /tools/:tool_id/mails/:mail_id/trash
      def destroy
        next_msg = find_next_message(@message, "trash")
        @message.update!(trashed: false)
        redirect_to_next_mail_or_fallback(next_msg, folder: "trash", notice: "Email restored.")
      end

      # DELETE /tools/:tool_id/mails/trash (empty trash)
      def destroy_all
        trashed = @tool.mail_account.messages.trashed
        trashed.where.not(uid: nil).find_each do |message|
          ImapSyncJob.perform_later(@tool.mail_account.id, "delete_message", message.uid, message.folder || "INBOX")
        end
        count = trashed.destroy_all.count
        redirect_to tool_mails_path(@tool, folder: "trash"), notice: "#{count} email(s) permanently deleted."
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.mail_account.messages.find(params[:mail_id])
      end

      def sync_delete_to_imap(message)
        return unless message.uid.present? && message.folder.present?
        account = @tool.mail_account
        ImapSyncService.new(account).delete_message(message.uid, folder: message.folder)
      end
    end
  end
end

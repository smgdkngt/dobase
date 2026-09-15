# frozen_string_literal: true

module Tools
  module Mails
    class ArchivesController < ApplicationController
      include ToolAuthorization
      include NextMailNavigation

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/archive
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        @message.update!(archived: true)
        sync_archive_to_imap

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email archived.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/archive
      def destroy
        next_msg = find_next_message(@message, "archive")
        @message.update!(archived: false)
        sync_unarchive_to_imap

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: "archive", notice: "Email unarchived.") }
          format.json { render "tools/mails/message" }
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end

      def sync_archive_to_imap
        return unless @message.uid.present?
        account = @tool.mail_account
        archive_folder = account.archive_folder.presence
        if archive_folder
          ImapSyncJob.perform_later(account.id, "move_to_folder", @message.uid, @message.folder || "INBOX", archive_folder)
        else
          ImapSyncJob.perform_later(account.id, "mark_as_read", @message.uid, @message.folder || "INBOX")
        end
      end

      def sync_unarchive_to_imap
        return unless @message.uid.present?
        account = @tool.mail_account
        archive_folder = account.archive_folder.presence
        if archive_folder
          ImapSyncJob.perform_later(account.id, "move_to_folder", @message.uid, archive_folder, "INBOX")
        else
          ImapSyncJob.perform_later(account.id, "mark_as_unread", @message.uid, @message.folder || "INBOX")
        end
      end
    end
  end
end

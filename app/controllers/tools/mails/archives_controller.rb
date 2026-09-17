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
        with_their_conversations([ @message ], folder: folder).reject(&:archived?).each do |message|
          message.update!(archived: true)
          sync_archive_to_imap(message)
        end

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email archived.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/archive
      def destroy
        next_msg = find_next_message(@message, "archive")
        with_their_conversations([ @message ], folder: "archive").select(&:archived?).each do |message|
          message.update!(archived: false)
          sync_unarchive_to_imap(message)
        end

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

      def sync_archive_to_imap(message)
        return unless message.uid.present?
        account = @tool.mail_account
        archive_folder = account.archive_folder.presence
        if archive_folder
          ImapSyncJob.perform_later(account.id, "move_to_folder", message.uid, message.folder || "INBOX", archive_folder)
        else
          ImapSyncJob.perform_later(account.id, "mark_as_read", message.uid, message.folder || "INBOX")
        end
      end

      def sync_unarchive_to_imap(message)
        return unless message.uid.present?
        account = @tool.mail_account
        archive_folder = account.archive_folder.presence
        if archive_folder
          # Archiving moved the message, which gave it a new UID in the archive folder. The UID we
          # have can be another message's there, so it's moved back by its Message-ID, and the
          # next sync gives it its new UID in the inbox.
          ImapSyncJob.perform_later(account.id, "move_to_folder_by_message_id", nil, archive_folder, "INBOX", message.message_id)
          message.update!(uid: nil)
        else
          ImapSyncJob.perform_later(account.id, "mark_as_unread", message.uid, message.folder || "INBOX")
        end
      end
    end
  end
end

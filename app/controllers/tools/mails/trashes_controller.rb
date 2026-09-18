# frozen_string_literal: true

module Tools
  module Mails
    class TrashesController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      # No access tokens: trashing deletes the message on the mail server right
      # away, and emptying the trash deletes it for good.
      before_action :set_message, only: %i[create destroy]

      # POST /tools/:tool_id/mails/:mail_id/trash
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        messages = with_their_conversations([ @message ], folder: folder).reject(&:trashed?)
        messages.each { |message| message.update!(trashed: true, archived: false) }
        sync_delete_to_imap(messages)

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email moved to trash.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/trash
      def destroy
        next_msg = find_next_message(@message, "trash")
        with_their_conversations([ @message ], folder: "trash").each { |message| message.update!(trashed: false) }

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: "trash", notice: "Email restored.") }
          format.json { render "tools/mails/message" }
        end
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

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end

      # One connection per folder
      def sync_delete_to_imap(messages)
        on_server = messages.select { |message| message.uid.present? && message.folder.present? }
        on_server.group_by(&:folder).each do |folder, in_folder|
          ImapSyncService.new(@tool.mail_account).delete_message(in_folder.map(&:uid), folder: folder)
        end
      end
    end
  end
end

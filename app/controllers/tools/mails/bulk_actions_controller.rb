# frozen_string_literal: true

module Tools
  module Mails
    class BulkActionsController < ApplicationController
      include ToolAuthorization
      include FolderValidation

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      # POST /tools/:tool_id/mails/bulk
      def create
        @mail_account = @tool.mail_account
        message_ids = params[:message_ids] || []
        action = params[:action_type]

        messages = @mail_account.messages.where(id: message_ids)

        notice = case action
        when "trash"
          messages.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, "delete_message", message.uid, message.folder || "INBOX")
          end
          messages.update_all(trashed: true, archived: false)
          "#{messages.count} email(s) moved to trash."
        when "archive"
          messages.update_all(archived: true)
          "#{messages.count} email(s) archived."
        when "mark_read"
          messages.update_all(read: true)
          messages.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, "mark_as_read", message.uid, message.folder || "INBOX")
          end
          "#{messages.count} email(s) marked as read."
        when "mark_unread"
          messages.update_all(read: false)
          messages.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, "mark_as_unread", message.uid, message.folder || "INBOX")
          end
          "#{messages.count} email(s) marked as unread."
        when "move_to_folder"
          target_folder = params[:target_folder].to_s.strip
          if valid_folder_name?(target_folder)
            messages.find_each do |message|
              source_folder = message.folder || "INBOX"
              message.update!(folder: target_folder, archived: false, trashed: false)
              if message.uid.present?
                ImapSyncJob.perform_later(@mail_account.id, "move_to_folder", message.uid, source_folder, target_folder)
              end
            end
            "#{messages.count} email(s) moved to #{target_folder}."
          else
            "Invalid folder name."
          end
        when "delete"
          trashed = messages.where(trashed: true)
          trashed.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, "delete_message", message.uid, message.folder || "INBOX")
          end
          count = trashed.destroy_all.count
          "#{count} email(s) permanently deleted."
        else
          "Unknown action."
        end

        redirect_back fallback_location: tool_mails_path(@tool), notice: notice
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

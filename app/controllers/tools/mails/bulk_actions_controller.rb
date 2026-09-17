# frozen_string_literal: true

module Tools
  module Mails
    class BulkActionsController < ApplicationController
      include ToolAuthorization
      include FolderValidation
      include NextMailNavigation

      # Each selected message can queue an IMAP job. Select-all in the mail list only covers the current page.
      MAX_MESSAGES = 200

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      # POST /tools/:tool_id/mails/bulk
      def create
        @mail_account = @tool.mail_account
        message_ids = Array.wrap(params[:message_ids])
        action = params[:action_type]

        if message_ids.size > MAX_MESSAGES
          redirect_back fallback_location: tool_mails_path(@tool), alert: "Select up to #{MAX_MESSAGES} emails at a time."
          return
        end

        messages = @mail_account.messages.where(id: message_ids)
        folder = params[:folder].presence || "inbox"

        notice = case action
        when "trash"
          messages = conversations_of(messages, folder).where(trashed: false)
          messages.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, "delete_message", message.uid, message.folder || "INBOX")
          end
          count = messages.update_all(trashed: true, trashed_at: Time.current, archived: false)
          "#{count} email(s) moved to trash."
        when "restore"
          # Local only, like TrashesController#destroy: trashing already expunged these on the IMAP server.
          count = conversations_of(messages, "trash").trashed.update_all(trashed: false, trashed_at: nil)
          "#{count} email(s) restored."
        when "archive"
          messages = conversations_of(messages, folder).where(archived: false)
          archive_folder = @mail_account.archive_folder.presence
          messages.where.not(uid: nil).find_each do |message|
            if archive_folder
              ImapSyncJob.perform_later(@mail_account.id, "move_to_folder", message.uid, message.folder || "INBOX", archive_folder)
            else
              ImapSyncJob.perform_later(@mail_account.id, "mark_as_read", message.uid, message.folder || "INBOX")
            end
          end
          count = messages.update_all(archived: true)
          "#{count} email(s) archived."
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
          trashed = conversations_of(messages, "trash").trashed
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

      def conversations_of(messages, folder)
        @mail_account.messages.where(id: with_their_conversations(messages, folder: folder).map(&:id))
      end
    end
  end
end

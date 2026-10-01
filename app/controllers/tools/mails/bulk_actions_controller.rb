# frozen_string_literal: true

module Tools
  module Mails
    class BulkActionsController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      # Each selected message can queue an IMAP job. Select-all in the mail list only covers the current page.
      MAX_MESSAGES = 200

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
          count = @mail_account.trash(conversations_of(messages, folder).to_a).size
          "#{count} email(s) moved to trash."
        when "restore"
          count = @mail_account.restore(conversations_of(messages, "trash").to_a).size
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
        when "mark_read", "mark_unread"
          read = action == "mark_read"
          messages = conversations_of(messages, folder).where(read: !read)
          messages.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, read ? "mark_as_read" : "mark_as_unread", message.uid, message.folder || "INBOX")
          end
          count = messages.update_all(read: read)
          "#{count} email(s) marked as #{read ? "read" : "unread"}."
        when "move_to_folder"
          target_folder = @mail_account.folder_to_move_to(params[:target_folder])
          if target_folder
            messages = conversations_of(messages, folder)
            moved = messages.to_a.each { |message| message.move_to_folder!(target_folder) }
            "#{moved.size} email(s) moved to #{helpers.mail_folder_name(target_folder)}."
          else
            "Invalid folder name."
          end
        when "delete"
          count = @mail_account.delete_for_good(conversations_of(messages, "trash").to_a).size
          "#{count} email(s) permanently deleted."
        else
          "Unknown action."
        end

        redirect_back fallback_location: tool_mails_path(@tool), notice: notice
      end

      private

      def conversations_of(messages, folder)
        @mail_account.messages.where(id: with_their_conversations(messages, folder: folder).map(&:id))
      end
    end
  end
end

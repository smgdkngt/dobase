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
          redirect_back fallback_location: tool_mails_path(@tool), alert: _("Select up to %{count} emails at a time.", count: MAX_MESSAGES)
          return
        end

        messages = @mail_account.messages.where(id: message_ids)
        folder = params[:folder].presence || "inbox"

        notice = case action
        when "trash"
          count = undoable(:put_back, conversations_of(messages, folder)) { @mail_account.trash(_1) }.size
          _("%{count} email(s) moved to trash.", count: count)
        when "restore"
          count = @mail_account.restore(conversations_of(messages, "trash").to_a).size
          _("%{count} email(s) restored.", count: count)
        when "archive"
          count = undoable(:unarchive, conversations_of(messages, folder)) { @mail_account.archive(_1) }.size
          _("%{count} email(s) archived.", count: count)
        when "junk"
          count = undoable(:put_back, conversations_of(messages, folder).not_draft) { @mail_account.mark_as_junk(_1) }.size
          _("%{count} email(s) moved to Junk.", count: count)
        when "not_junk"
          count = undoable(:put_back, conversations_of(messages, "junk")) { @mail_account.not_junk(_1) }.size
          _("%{count} email(s) moved to the inbox.", count: count)
        when "mark_read", "mark_unread"
          read = action == "mark_read"
          messages = conversations_of(messages, folder).where(read: !read)
          messages.where.not(uid: nil).find_each do |message|
            ImapSyncJob.perform_later(@mail_account.id, read ? "mark_as_read" : "mark_as_unread", message.uid, message.folder || "INBOX")
          end
          count = messages.update_all(read: read)
          read ? _("%{count} email(s) marked as read.", count: count) : _("%{count} email(s) marked as unread.", count: count)
        when "move_to_folder"
          target_folder = @mail_account.folder_to_move_to(params[:target_folder])
          if target_folder
            moved = undoable(:put_back, conversations_of(messages, folder)) { @mail_account.move(_1, target_folder) }
            _("%{count} email(s) moved to %{folder}.", count: moved.size, folder: helpers.mail_folder_name(target_folder))
          else
            _("Invalid folder name.")
          end
        when "delete"
          count = @mail_account.delete_for_good(conversations_of(messages, "trash").to_a).size
          _("%{count} email(s) permanently deleted.", count: count)
        else
          _("Unknown action.")
        end

        redirect_back fallback_location: tool_mails_path(@tool), notice: notice
      end

      private

      # A search over every folder ("all") has its conversations each in its own folder
      def conversations_of(messages, folder)
        by_folder = folder == "all" ? messages.group_by { |message| @mail_account.view_of(message) } : { folder => messages }
        @mail_account.messages.where(id: by_folder.flat_map { |each_folder, its| with_their_conversations(its, folder: each_folder).map(&:id) })
      end
    end
  end
end

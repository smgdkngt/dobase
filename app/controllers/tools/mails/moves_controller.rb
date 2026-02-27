# frozen_string_literal: true

module Tools
  module Mails
    class MovesController < ApplicationController
      include ToolAuthorization
      include FolderValidation

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/move
      def create
        target_folder = params[:folder].to_s.strip

        unless valid_folder_name?(target_folder)
          redirect_back fallback_location: tool_mails_path(@tool), alert: "Invalid folder name."
          return
        end

        source_folder = @message.folder || "INBOX"
        @message.update!(folder: target_folder, archived: false, trashed: false)

        if @message.uid.present?
          ImapSyncJob.perform_later(@tool.mail_account.id, "move_to_folder", @message.uid, source_folder, target_folder)
        end

        redirect_back fallback_location: tool_mails_path(@tool, folder: target_folder), notice: "Moved to #{target_folder}."
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.mail_account.messages.find(params[:mail_id])
      end
    end
  end
end

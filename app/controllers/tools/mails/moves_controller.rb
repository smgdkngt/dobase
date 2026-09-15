# frozen_string_literal: true

module Tools
  module Mails
    class MovesController < ApplicationController
      include ToolAuthorization
      include FolderValidation
      include NextMailNavigation

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/move
      def create
        target_folder = params[:folder].to_s.strip

        unless valid_folder_name?(target_folder)
          respond_to do |format|
            format.html { redirect_back fallback_location: tool_mails_path(@tool), alert: "Invalid folder name." }
            format.json { render json: { errors: [ "Invalid folder name" ] }, status: :unprocessable_entity }
          end
          return
        end

        source_folder = @message.folder || "INBOX"
        current_folder = params[:current_folder] || "inbox"
        next_msg = find_next_message(@message, current_folder)

        @message.update!(folder: target_folder, archived: false, trashed: false)

        if @message.uid.present?
          ImapSyncJob.perform_later(@tool.mail_account.id, "move_to_folder", @message.uid, source_folder, target_folder)
        end

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: current_folder, notice: "Moved to #{target_folder}.") }
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
    end
  end
end

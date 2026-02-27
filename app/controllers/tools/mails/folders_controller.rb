# frozen_string_literal: true

module Tools
  module Mails
    class FoldersController < ApplicationController
      include ToolAuthorization
      include FolderValidation

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      # POST /tools/:tool_id/mails/folder
      def create
        folder_name = params[:folder_name].to_s.strip

        unless valid_folder_name?(folder_name)
          redirect_to tool_mails_path(@tool), alert: "Invalid folder name."
          return
        end

        ImapSyncService.new(@tool.mail_account).create_folder(folder_name)
        redirect_to tool_mails_path(@tool, folder: folder_name), notice: "Folder \"#{folder_name}\" created."
      rescue StandardError => e
        redirect_to tool_mails_path(@tool), alert: "Could not create folder: #{e.message}"
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

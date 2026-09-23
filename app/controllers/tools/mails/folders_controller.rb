# frozen_string_literal: true

module Tools
  module Mails
    class FoldersController < ApplicationController
      include ToolScoped
      include FolderValidation

      restrict_in_demo only: :create

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
    end
  end
end

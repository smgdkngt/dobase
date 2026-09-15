# frozen_string_literal: true

module Tools
  module Files
    # Deletes what's selected in the file manager, folders with everything in them.
    # The whole selection goes in one request and one transaction, so a failure
    # doesn't leave it half deleted.
    class DeletionsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def create
        folders = @tool.file_folders.where(id: params[:folder_ids])
        files = @tool.file_items.where(id: params[:file_ids])
        raise ActiveRecord::RecordNotFound if folders.none? && files.none?

        ActiveRecord::Base.transaction do
          folders.each(&:destroy!)
          files.each(&:destroy!)
        end

        redirect_back_or_to tool_files_path(@tool)
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

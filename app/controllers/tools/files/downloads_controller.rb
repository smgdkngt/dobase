# frozen_string_literal: true

module Tools
  module Files
    # Downloads what's selected in the file manager with a single request, because
    # browsers block or ask about several downloads started by one click. The ids
    # come in a POST body: a few hundred of them don't fit in a URL.
    class DownloadsController < ApplicationController
      include ToolAuthorization
      include FolderArchiveDownload

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_selection

      # One file or folder downloads the way it does on its own; more come as one zip.
      def create
        if @files.one? && @folders.none?
          redirect_to tool_files_item_download_path(@tool, @files.first)
        elsif @folders.one? && @files.none?
          redirect_to tool_files_folder_download_path(@tool, @folders.first)
        else
          send_selection_archive
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_selection
        @files = @tool.file_items.where(id: params[:file_ids]).to_a
        @folders = @tool.file_folders.where(id: params[:folder_ids]).to_a
        raise ActiveRecord::RecordNotFound if @files.none? && @folders.none?
      end

      def send_selection_archive
        archive = ::Files::SelectionArchive.new(@tool, folders: @folders, files: @files)

        if archive.too_large?
          redirect_back_or_to tool_files_path(@tool),
            alert: "The selection is too large to download as a zip. Zips are limited to " \
                   "#{helpers.number_to_human_size(::Files::FolderArchive::MAX_BYTES)} and " \
                   "#{helpers.number_with_delimiter(::Files::FolderArchive::MAX_FILES)} files."
        else
          send_folder_archive archive
        end
      end
    end
  end
end

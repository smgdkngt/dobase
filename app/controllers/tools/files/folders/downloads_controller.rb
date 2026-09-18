# frozen_string_literal: true

module Tools
  module Files
    module Folders
      class DownloadsController < ApplicationController
        include ToolScoped
        include FolderArchiveDownload

        allow_access_tokens
        before_action :set_folder

        def show
          archive = ::Files::FolderArchive.new(@folder)

          if archive.too_large?
            refuse_too_large_archive
          else
            send_folder_archive archive
          end
        end

        private

        def set_folder
          @folder = @tool.file_folders.find(params[:folder_id])
        end

        # A browser goes back to the folder listing with an explanation; anything else gets it with a 413.
        def refuse_too_large_archive
          message = "#{@folder.name} is too large to download as a zip. Zips are limited to " \
                    "#{helpers.number_to_human_size(::Files::FolderArchive::MAX_BYTES)} and " \
                    "#{helpers.number_with_delimiter(::Files::FolderArchive::MAX_FILES)} files."

          if request.format.html?
            redirect_to tool_files_path(@tool, folder_id: @folder.parent_id), alert: message
          else
            render json: { error: message }, status: :content_too_large
          end
        end
      end
    end
  end
end

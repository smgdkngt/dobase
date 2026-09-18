# frozen_string_literal: true

module Tools
  class FilesController < ApplicationController
    include ToolScoped

    allow_access_tokens
    before_action :set_folder, only: :show

    def show
      @folders = current_folders.ordered.includes(:share)
      @files = current_files.ordered.includes(:share)

      respond_to do |format|
        format.html do
          @ancestors = @folder&.breadcrumbs || []
          @view_mode = params[:view].presence_in(%w[grid list]) || cookies[:files_view] || "grid"

          # Save preference to cookie if changed via URL param
          if params[:view].present? && params[:view] != cookies[:files_view]
            cookies[:files_view] = { value: params[:view], expires: 1.year.from_now }
          end
        end
        format.json
      end
    end

    private

    def set_folder
      @folder = @tool.file_folders.find(params[:folder_id]) if params[:folder_id].present?
    end

    def current_folders
      @folder ? @folder.children : @tool.file_folders.roots
    end

    def current_files
      @folder ? @folder.files : @tool.file_items.roots
    end
  end
end

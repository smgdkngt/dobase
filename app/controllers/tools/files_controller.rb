# frozen_string_literal: true

module Tools
  class FilesController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
    before_action :set_folder, only: :show

    def show
      @folders = current_folders.ordered
      @files = current_files.ordered
      @ancestors = @folder&.breadcrumbs || []
      @view_mode = params[:view].presence_in(%w[grid list]) || cookies[:files_view] || "grid"

      # Save preference to cookie if changed via URL param
      if params[:view].present? && params[:view] != cookies[:files_view]
        cookies[:files_view] = { value: params[:view], expires: 1.year.from_now }
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

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

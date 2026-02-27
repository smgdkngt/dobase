# frozen_string_literal: true

module Tools
  module Files
    class FoldersController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action :set_folder, only: %i[update destroy]
      before_action -> { authorize_tool_access!(@tool) }

      def create
        parent = params[:parent_id].present? ? @tool.file_folders.find(params[:parent_id]) : nil
        position = (parent&.children || @tool.file_folders.roots).maximum(:position).to_i + 1

        @folder = @tool.file_folders.create!(
          name: params[:name].presence || "New Folder",
          parent: parent,
          position: position
        )

        redirect_to tool_files_path(@tool, folder_id: parent&.id)
      end

      def update
        @folder.update!(folder_params)
        render json: { id: @folder.id, name: @folder.name }
      end

      def destroy
        parent_id = @folder.parent_id
        @folder.destroy!

        respond_to do |format|
          format.html { redirect_to tool_files_path(@tool, folder_id: parent_id) }
          format.json { head :no_content }
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_folder
        @folder = @tool.file_folders.find(params[:id])
      end

      def folder_params
        params.require(:folder).permit(:name, :parent_id)
      end
    end
  end
end

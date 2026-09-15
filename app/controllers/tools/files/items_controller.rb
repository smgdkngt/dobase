# frozen_string_literal: true

module Tools
  module Files
    class ItemsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens
      # API clients send name and folder_id at the top level; the web sends them under file.
      wrap_parameters :file, include: %i[name folder_id]

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_file

      def show
        respond_to do |format|
          format.html { @siblings = (@file.folder&.files || @tool.file_items.roots).ordered.where.not(id: @file.id) }
          format.json
        end
      end

      def update
        if @file.update(file_params.merge(updated_by: current_user))
          render :show, formats: :json
        else
          render json: { errors: @file.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        folder_id = @file.folder_id
        @file.destroy!

        respond_to do |format|
          format.html { redirect_to tool_files_path(@tool, folder_id: folder_id) }
          format.json { head :no_content }
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_file
        @file = @tool.file_items.find(params[:id])
      end

      # A file can only move into a folder of this tool. A blank folder_id is the top level.
      def file_params
        params.require(:file).permit(:name, :folder_id).tap do |permitted|
          permitted[:folder_id] = @tool.file_folders.find(permitted[:folder_id]).id if permitted[:folder_id].present?
        end
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  module Files
    class ItemsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action :set_file
      before_action -> { authorize_tool_access!(@tool) }

      def show
        @siblings = (@file.folder&.files || @tool.file_items.roots).ordered.where.not(id: @file.id)
      end

      def update
        if @file.update(file_params)
          render json: { id: @file.id, name: @file.name }
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

      def file_params
        params.require(:file).permit(:name, :folder_id)
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  module Files
    class UploadsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def create
        folder = params[:folder_id].present? ? @tool.file_folders.find(params[:folder_id]) : nil
        base_position = (folder&.files || @tool.file_items.roots).maximum(:position).to_i

        # Handle multiple files
        files = Array(params[:files].presence || params[:file])
        errors = []

        files.each_with_index do |uploaded_file, index|
          next unless uploaded_file.respond_to?(:original_filename)

          file_item = @tool.file_items.new(
            name: uploaded_file.original_filename,
            folder: folder,
            position: base_position + index + 1
          )
          file_item.file.attach(uploaded_file)

          unless file_item.save
            errors.concat(file_item.errors.full_messages)
          end
        end

        respond_to do |format|
          if errors.empty?
            format.html { redirect_to tool_files_path(@tool, folder_id: folder&.id) }
            format.json { render json: { success: true } }
          else
            format.html { redirect_to tool_files_path(@tool, folder_id: folder&.id), alert: errors.join(", ") }
            format.json { render json: { errors: errors }, status: :unprocessable_entity }
          end
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

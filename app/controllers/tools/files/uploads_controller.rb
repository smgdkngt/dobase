# frozen_string_literal: true

module Tools
  module Files
    class UploadsController < ApplicationController
      include ToolScoped

      restrict_in_demo only: :create

      allow_access_tokens

      # Takes files[] (or a single file) and an optional folder_id. Either every
      # file is saved or, when one of them is refused, none are.
      def create
        folder = params[:folder_id].present? ? @tool.file_folders.find(params[:folder_id]) : nil
        @files = build_files(folder)
        errors = upload_errors

        if errors.empty?
          ApplicationRecord.transaction { @files.each(&:save!) }
          notify_uploads
        end

        respond_to do |format|
          if errors.empty?
            format.html { redirect_to tool_files_path(@tool, folder_id: folder&.id) }
            format.json { render :create, status: :created }
          else
            format.html { redirect_to tool_files_path(@tool, folder_id: folder&.id), alert: errors.join(", ") }
            format.json { render json: { errors: errors }, status: :unprocessable_entity }
          end
        end
      end

      private

      def build_files(folder)
        uploaded_files = Array(params[:files].presence || params[:file]).select { |uploaded_file| uploaded_file.respond_to?(:original_filename) }
        base_position = (folder&.files || @tool.file_items.roots).maximum(:position).to_i

        uploaded_files.each_with_index.map do |uploaded_file, index|
          file_item = @tool.file_items.new(
            name: uploaded_file.original_filename,
            folder: folder,
            position: base_position + index + 1,
            created_by: current_user,
            updated_by: current_user
          )
          file_item.file.attach(uploaded_file)
          file_item
        end
      end

      # Each message names its file, so a refused file is easy to find among many.
      def upload_errors
        return [ "No file was uploaded" ] if @files.empty?

        @files.reject(&:valid?).flat_map do |file_item|
          file_item.errors.full_messages.map { |message| "#{file_item.name}: #{message}" }
        end
      end

      def notify_uploads
        recipients = @tool.notifiable_users.where.not(id: current_user.id)
        return if recipients.none?

        FileUploadedNotifier.with(file: @files.last, uploader: current_user, tool: @tool).deliver(recipients)
        recipients.each(&:prune_notifications!)
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class AttachmentsController < ApplicationController
        include ToolScoped

        allow_access_tokens
        before_action :set_item
        before_action :set_attachment, only: :destroy

        MAX_ATTACHMENT_SIZE = 25.megabytes

        def create
          files = uploaded_files
          head :unprocessable_entity and return if files.empty?

          limit = Demo.upload_limit(MAX_ATTACHMENT_SIZE)
          if files.any? { |file| file.size > limit }
            respond_to do |format|
              format.html { redirect_to tool_todo_item_path(@tool, @item), alert: "File too large (max #{limit / 1.megabyte} MB)." }
              format.json { render json: { errors: [ "File too large (max #{limit / 1.megabyte} MB)" ] }, status: :unprocessable_entity }
            end
            return
          end

          attachments = files.map { |file| build_attachment(file) }
          if attachments.all?(&:valid?)
            attachments.each(&:save!)
            @attachment = attachments.last

            respond_to do |format|
              format.html { redirect_to tool_todo_item_path(@tool, @item) }
              format.json { render :show, status: :created }
            end
          else
            errors = attachments.flat_map { |attachment| attachment.errors.full_messages }.uniq
            respond_to do |format|
              format.html { redirect_to tool_todo_item_path(@tool, @item), alert: errors.first }
              format.json { render json: { errors: errors }, status: :unprocessable_entity }
            end
          end
        end

        def destroy
          @attachment.destroy!

          respond_to do |format|
            format.html { redirect_to tool_todo_item_path(@tool, @item) }
            format.json { head :no_content }
          end
        end

        private

        # The browser sends files[] (several can be picked at once), the API a single file
        def uploaded_files
          Array(params[:files].presence || params[:file]).grep(ActionDispatch::Http::UploadedFile)
        end

        # Built with its file, so the file is checked before anything is saved
        def build_attachment(file)
          @item.attachments.build(filename: file.original_filename, content_type: file.content_type, file_size: file.size, file: file)
        end

        def set_item
          @item = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }).find(params[:item_id])
        end

        def set_attachment
          @attachment = @item.attachments.find(params[:id])
        end
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class AttachmentsController < ApplicationController
        include ToolAuthorization

        allow_access_tokens

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_item
        before_action :set_attachment, only: :destroy

        MAX_ATTACHMENT_SIZE = 25.megabytes

        def create
          files = uploaded_files
          head :unprocessable_entity and return if files.empty?

          if files.any? { |file| file.size > MAX_ATTACHMENT_SIZE }
            respond_to do |format|
              format.html { redirect_to tool_todo_item_path(@tool, @item), alert: "File too large (max 25 MB)." }
              format.json { render json: { errors: [ "File too large (max 25 MB)" ] }, status: :unprocessable_entity }
            end
            return
          end

          @attachment = files.map { |file| attach(file) }.last

          respond_to do |format|
            format.html { redirect_to tool_todo_item_path(@tool, @item) }
            format.json { render :show, status: :created }
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

        def attach(file)
          @item.attachments.create!(filename: file.original_filename, content_type: file.content_type, file_size: file.size).tap do |attachment|
            attachment.file.attach(file)
          end
        end

        def set_tool
          @tool = Tool.find(params[:tool_id])
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

# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class AttachmentsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_item
        before_action :set_attachment, only: :destroy

        MAX_ATTACHMENT_SIZE = 25.megabytes

        def create
          file = params[:file]

          unless file.is_a?(ActionDispatch::Http::UploadedFile)
            head :unprocessable_entity and return
          end

          if file.size > MAX_ATTACHMENT_SIZE
            redirect_to tool_todo_item_path(@tool, @item), alert: "File too large (max 25 MB)."
            return
          end

          attachment = @item.attachments.create!(
            filename: file.original_filename,
            content_type: file.content_type,
            file_size: file.size
          )
          attachment.file.attach(file)

          redirect_to tool_todo_item_path(@tool, @item)
        end

        def destroy
          @attachment.destroy!
          redirect_to tool_todo_item_path(@tool, @item)
        end

        private

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

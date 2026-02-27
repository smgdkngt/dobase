# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class AttachmentsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_card
        before_action :set_attachment, only: :destroy

        MAX_ATTACHMENT_SIZE = 25.megabytes

        def create
          file = params[:file]

          unless file.is_a?(ActionDispatch::Http::UploadedFile)
            head :unprocessable_entity and return
          end

          if file.size > MAX_ATTACHMENT_SIZE
            redirect_to tool_board_card_path(@tool, @card), alert: "File too large (max 25 MB)."
            return
          end

          attachment = @card.attachments.create!(
            filename: file.original_filename,
            content_type: file.content_type,
            file_size: file.size
          )
          attachment.file.attach(file)

          redirect_to tool_board_card_path(@tool, @card)
        end

        def destroy
          @attachment.destroy!
          redirect_to tool_board_card_path(@tool, @card)
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_card
          @card = @tool.board.cards.find(params[:card_id])
        end

        def set_attachment
          @attachment = @card.attachments.find(params[:id])
        end
      end
    end
  end
end

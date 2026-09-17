# frozen_string_literal: true

module Tools
  module Boards
    module Cards
      class AttachmentsController < ApplicationController
        include ToolAuthorization

        allow_access_tokens

        before_action :set_tool
        before_action -> { authorize_tool_access!(@tool) }
        before_action :set_card
        before_action :set_attachment, only: :destroy

        MAX_ATTACHMENT_SIZE = 25.megabytes

        def create
          files = uploaded_files
          head :unprocessable_entity and return if files.empty?

          if files.any? { |file| file.size > MAX_ATTACHMENT_SIZE }
            respond_to do |format|
              format.html { redirect_to tool_board_card_path(@tool, @card), alert: "File too large (max 25 MB)." }
              format.json { render json: { errors: [ "File too large (max 25 MB)" ] }, status: :unprocessable_entity }
            end
            return
          end

          attachments = files.map { |file| build_attachment(file) }
          if attachments.all?(&:valid?)
            attachments.each(&:save!)
            @attachment = attachments.last

            respond_to do |format|
              format.html { redirect_to tool_board_card_path(@tool, @card) }
              format.json { render :show, status: :created }
            end
          else
            errors = attachments.flat_map { |attachment| attachment.errors.full_messages }.uniq
            respond_to do |format|
              format.html { redirect_to tool_board_card_path(@tool, @card), alert: errors.first }
              format.json { render json: { errors: errors }, status: :unprocessable_entity }
            end
          end
        end

        def destroy
          @attachment.destroy!

          respond_to do |format|
            format.html { redirect_to tool_board_card_path(@tool, @card) }
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
          @card.attachments.build(filename: file.original_filename, content_type: file.content_type, file_size: file.size, file: file)
        end

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

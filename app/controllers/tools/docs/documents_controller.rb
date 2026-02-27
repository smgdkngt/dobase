# frozen_string_literal: true

module Tools
  module Docs
    class DocumentsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action :set_document, only: %i[show edit update destroy]
      before_action -> { authorize_tool_access!(@tool) }

      def show
        @locked_by = @document.locked? ? @document.locked_by : nil
      end

      def edit
        # Atomic lock acquisition: only update if not locked or lock expired or we own it
        rows_updated = ::Docs::Document.where(id: @document.id)
          .where(
            "locked_by_id IS NULL OR locked_at < ? OR locked_by_id = ?",
            ::Docs::Document::LOCK_TIMEOUT.ago,
            current_user.id
          )
          .update_all(locked_by_id: current_user.id, locked_at: Time.current)

        if rows_updated.zero?
          @document.reload
          redirect_to tool_docs_document_path(@tool, @document),
            notice: "#{@document.locked_by&.name || 'Someone'} is currently editing this document."
          return
        end

        @document.reload
      end

      def create
        @document = @tool.documents.build(
          title: "Untitled",
          last_edited_by: current_user,
          last_edited_at: Time.current
        )

        if @document.save
          redirect_to edit_tool_docs_document_path(@tool, @document)
        else
          redirect_to tool_docs_path(@tool), alert: "Could not create document."
        end
      end

      def update
        @document.assign_attributes(document_params)
        @document.last_edited_by = current_user
        @document.last_edited_at = Time.current

        respond_to do |format|
          if @document.save
            @document.broadcast_content_update
            format.html { redirect_to edit_tool_docs_document_path(@tool, @document) }
            format.json { render json: { saved: true, updated_at: @document.updated_at } }
          else
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: { errors: @document.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        @document.destroy
        redirect_to tool_docs_path(@tool), notice: "Document deleted."
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_document
        @document = @tool.documents.find(params[:id])
      end

      def document_params
        params.require(:docs_document).permit(:title, :content)
      end
    end
  end
end

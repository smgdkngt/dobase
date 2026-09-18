# frozen_string_literal: true

module Tools
  module Docs
    class DocumentsController < ApplicationController
      include ToolScoped

      # Opening the editor takes the document's lock, which only the browser editor keeps alive.
      allow_access_tokens only: %i[show create update destroy]
      before_action :set_document, only: %i[show edit update destroy]
      before_action :refuse_while_someone_else_is_editing, only: %i[update destroy]

      def show
        @locked_by = @document.locked? ? @document.locked_by : nil
        @presence_context = "document:#{@document.id}"
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
          created_by: current_user,
          updated_by: current_user,
          last_edited_at: Time.current
        )
        # The browser starts from an untitled, empty document; API clients can send a title and content.
        @document.assign_attributes(params.fetch(:docs_document, {}).permit(:title, :content))

        respond_to do |format|
          if @document.save
            notify_document_created
            format.html { redirect_to edit_tool_docs_document_path(@tool, @document) }
            format.json { render :show, status: :created }
          else
            format.html { redirect_to tool_docs_path(@tool), alert: "Could not create document." }
            format.json { render json: { errors: @document.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def update
        @document.assign_attributes(document_params)
        @document.updated_by = current_user
        @document.last_edited_at = Time.current

        respond_to do |format|
          if @document.save
            @document.broadcast_content_update
            format.html { redirect_to edit_tool_docs_document_path(@tool, @document) }
            format.json { render :show }
          else
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: { errors: @document.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        @document.destroy

        respond_to do |format|
          format.html { redirect_to tool_docs_path(@tool), notice: "Document deleted." }
          format.json { head :no_content }
        end
      end

      private

      def set_document
        @document = @tool.documents.find(params[:id])
      end

      def document_params
        params.require(:docs_document).permit(:title, :content)
      end

      # Whoever holds the lock has the document open in the editor, which autosaves
      # over any change made in the meantime. Their own saves go through.
      def refuse_while_someone_else_is_editing
        return unless @document.locked? && @document.locked_by_id != current_user.id

        message = "#{@document.locked_by&.name || 'Someone'} is editing this document"
        respond_to do |format|
          format.html { redirect_to tool_docs_document_path(@tool, @document), alert: message }
          format.json { render json: { error: message }, status: :conflict }
        end
      end

      def notify_document_created
        recipients = @tool.notifiable_users.where.not(id: current_user.id)
        return if recipients.none?

        DocumentCreatedNotifier.with(document: @document, creator: current_user, tool: @tool).deliver(recipients)
        recipients.each(&:prune_notifications!)
      end
    end
  end
end

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
        current_user.read_notifications_about!(records: [ @document ], urls: [ tool_docs_document_path(@tool, @document) ])
      end

      # Everyone may open the editor at once: the text is a shared copy that
      # merges what people type (see DocumentSyncChannel). Having it open is
      # recorded from there, for the documents list and the API to read.
      def edit
        @presence_context = "document:#{@document.id}"
        current_user.read_notifications_about!(records: [ @document ], urls: [ tool_docs_document_path(@tool, @document) ])
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
            # A write from outside the editor replaces the text, so the copy the
            # editors share has to start again from it — otherwise the next
            # keystroke in an open editor would put the old text straight back.
            @document.reset_shared_copy! if access_token_request?
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

      # People writing in the editor share one copy of the text, which merges
      # what they type; they never get in each other's way. A write from outside
      # it replaces the lot, so that one waits until the editors have left.
      def refuse_while_someone_else_is_editing
        return unless access_token_request?
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

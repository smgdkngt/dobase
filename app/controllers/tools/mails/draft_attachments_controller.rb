# frozen_string_literal: true

module Tools
  module Mails
    class DraftAttachmentsController < ApplicationController
      include ToolScoped

      # What most mail servers take in one email, and Base64 makes files a third bigger on the way
      MAX_SIZE = 25.megabytes

      allow_access_tokens
      before_action :set_draft

      # POST /tools/:tool_id/mails/drafts/:mail_draft_id/attachments
      def create
        files = Array(params[:files]).select { |file| file.respond_to?(:original_filename) }

        if files.empty?
          render json: { errors: [ "No files to attach" ] }, status: :unprocessable_entity
        elsif @draft.attachments.sum(:file_size) + files.sum(&:size) > MAX_SIZE
          render json: { errors: [ "A draft's attachments can be #{helpers.human_file_size(MAX_SIZE)} together" ] }, status: :unprocessable_entity
        else
          @draft.attach_uploads(files)
          @draft.sent_at = Time.current
          @draft.save!
          SyncDraftJob.perform_later(@draft.id)
          render "tools/mails/drafts/show", formats: :json, status: :created
        end
      end

      private

      def set_draft
        @draft = @tool.mail_account&.messages&.drafts&.find_by(id: params[:mail_draft_id])
        return if @draft

        render json: { error: @tool.mail_account ? "Not found" : "Mail account not configured" }, status: :not_found
      end
    end
  end
end

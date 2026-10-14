# frozen_string_literal: true

module Tools
  module Mails
    # Junk is the server's junk folder: mail is moved there, and out of it to the inbox
    class JunksController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      allow_access_tokens
      before_action :set_message
      before_action :require_junk_folder, only: :create

      # POST /tools/:tool_id/mails/:mail_id/junk
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        @tool.mail_account.mark_as_junk(with_their_conversations([ @message ], folder: folder))

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Moved to Junk.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/junk
      def destroy
        next_msg = find_next_message(@message, "junk")
        @tool.mail_account.not_junk(with_their_conversations([ @message ], folder: "junk"))

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: "junk", notice: "Moved to the inbox.") }
          format.json { render "tools/mails/message" }
        end
      end

      private

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).not_draft.find(params[:mail_id])
      end

      def require_junk_folder
        return if @tool.mail_account.junk_folder?

        respond_to do |format|
          format.html { redirect_back_or_to tool_mails_path(@tool), alert: "This account's mail server has no junk folder." }
          format.json { render json: { error: "This account's mail server has no junk folder." }, status: :unprocessable_entity }
        end
      end
    end
  end
end

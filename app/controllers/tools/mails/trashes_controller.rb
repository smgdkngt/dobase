# frozen_string_literal: true

module Tools
  module Mails
    class TrashesController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      # Access tokens trash and restore, never empty the trash: that deletes mail for good.
      allow_access_tokens only: %i[create destroy]
      before_action :set_message, only: %i[create destroy]
      before_action :require_server_trash, only: :create, if: :access_token_request?

      # POST /tools/:tool_id/mails/:mail_id/trash
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        # A draft is discarded by itself: the conversation it answers stays where it is
        @tool.mail_account.trash(@message.draft? ? [ @message ] : with_their_conversations([ @message ], folder: folder))

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email moved to trash.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/trash
      def destroy
        next_msg = find_next_message(@message, "trash")
        @tool.mail_account.restore(@message.draft? ? [ @message ] : with_their_conversations([ @message ], folder: "trash"))

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: "trash", notice: "Email restored.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/trash (empty trash)
      def destroy_all
        count = @tool.mail_account.delete_for_good(@tool.mail_account.messages.trashed.to_a).size
        redirect_to tool_mails_path(@tool, folder: "trash"), notice: "#{count} email(s) permanently deleted."
      end

      private

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end

      # On a mail server without a trash folder, trashing deletes the mail there right away.
      # That stays in the browser.
      def require_server_trash
        return if @tool.mail_account.server_trash?

        render json: { error: "This account's mail server has no trash folder, so trashing would delete the mail there. Archive it instead." },
          status: :unprocessable_entity
      end
    end
  end
end

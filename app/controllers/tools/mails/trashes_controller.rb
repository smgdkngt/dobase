# frozen_string_literal: true

module Tools
  module Mails
    class TrashesController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      # No access tokens: trashing deletes the message on the mail server right
      # away, and emptying the trash deletes it for good.
      before_action :set_message, only: %i[create destroy]

      # POST /tools/:tool_id/mails/:mail_id/trash
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        @tool.mail_account.trash(with_their_conversations([ @message ], folder: folder))

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email moved to trash.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/trash
      def destroy
        next_msg = find_next_message(@message, "trash")
        @tool.mail_account.restore(with_their_conversations([ @message ], folder: "trash"))

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
    end
  end
end

# frozen_string_literal: true

module Tools
  module Mails
    # Mail sent off from the compose page waits a moment before it goes out (SendMailJob).
    # Undo in that moment takes it back: it's a draft again, and the compose page opens
    # with it as it was.
    class SendingsController < ApplicationController
      include ToolScoped

      # DELETE /tools/:tool_id/mails/:mail_id/sending
      def destroy
        message = @tool.mail_account.messages.find(params[:mail_id])
        folder = params[:folder].presence || "inbox"

        if message.take_back!
          # It left the server's Drafts when it was sent off: there it is again
          SyncDraftJob.perform_later(message.id)
          redirect_to new_tool_mail_path(@tool, draft_id: message.id, folder: folder)
        else
          redirect_back_or_to tool_mail_path(@tool, message, folder: folder), alert: "Too late to undo: it's on its way."
        end
      end
    end
  end
end

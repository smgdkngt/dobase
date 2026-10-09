# frozen_string_literal: true

module Tools
  module Mails
    class ArchivesController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      allow_access_tokens
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/archive
      def create
        folder = params[:folder] || "inbox"
        next_msg = find_next_message(@message, folder)
        account.archive(with_their_conversations([ @message ], folder: folder))

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email archived.") }
          format.json { render "tools/mails/message" }
        end
      end

      # DELETE /tools/:tool_id/mails/:mail_id/archive
      def destroy
        next_msg = find_next_message(@message, "archive")
        conversation = with_their_conversations([ @message ], folder: "archive")
        account.unarchive(conversation)
        # The copy in the server's archive folder left with the mail itself, which is shown
        @message = conversation.find { |message| message.persisted? && message.message_id == @message.message_id } if @message.destroyed?

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: "archive", notice: "Email unarchived.") }
          format.json { render "tools/mails/message" }
        end
      end

      private

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end

      def account
        @tool.mail_account
      end
    end
  end
end

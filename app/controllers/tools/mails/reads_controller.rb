# frozen_string_literal: true

module Tools
  module Mails
    class ReadsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/read
      # The message copies the change to the mail server itself
      def create
        @message.mark_as_read!
        respond_with_message
      end

      # DELETE /tools/:tool_id/mails/:mail_id/read
      def destroy
        @message.mark_as_unread!
        respond_with_message
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end

      def respond_with_message
        respond_to do |format|
          format.html { redirect_back fallback_location: tool_mails_path(@tool) }
          format.json { render "tools/mails/message" }
        end
      end
    end
  end
end

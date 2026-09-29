# frozen_string_literal: true

module Tools
  module Mails
    # Always show images in mail from a message's sender, or stop doing so
    class TrustedSendersController < ApplicationController
      include ToolScoped

      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/trusted_sender
      def create
        @tool.mail_account.trusted_senders.find_or_create_by!(email_address: @message.from_address)
        redirect_back fallback_location: tool_mail_path(@tool, @message)
      end

      # DELETE /tools/:tool_id/mails/:mail_id/trusted_sender
      def destroy
        @tool.mail_account.trusted_senders.where(email_address: @message.from_address).delete_all
        redirect_back fallback_location: tool_mail_path(@tool, @message)
      end

      private

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end
    end
  end
end

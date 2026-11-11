# frozen_string_literal: true

module Tools
  module Mails
    class StarsController < ApplicationController
      include ToolScoped

      allow_access_tokens
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/star
      def create
        @message.set_starred!(true)
        respond_with_message
      end

      # DELETE /tools/:tool_id/mails/:mail_id/star
      def destroy
        @message.set_starred!(false)
        respond_with_message
      end

      private

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

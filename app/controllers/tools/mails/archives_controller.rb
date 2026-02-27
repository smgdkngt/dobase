# frozen_string_literal: true

module Tools
  module Mails
    class ArchivesController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/archive
      def create
        @message.update!(archived: true)
        redirect_back fallback_location: tool_mails_path(@tool), notice: "Email archived."
      end

      # DELETE /tools/:tool_id/mails/:mail_id/archive
      def destroy
        @message.update!(archived: false)
        redirect_back fallback_location: tool_mails_path(@tool, folder: "archive"), notice: "Email unarchived."
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.mail_account.messages.find(params[:mail_id])
      end
    end
  end
end

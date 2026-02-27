# frozen_string_literal: true

module Tools
  module Mails
    class TrashesController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message, only: %i[create destroy]

      # POST /tools/:tool_id/mails/:mail_id/trash
      def create
        @message.update!(trashed: true, archived: false)
        redirect_back fallback_location: tool_mails_path(@tool), notice: "Email moved to trash."
      end

      # DELETE /tools/:tool_id/mails/:mail_id/trash
      def destroy
        @message.update!(trashed: false)
        redirect_back fallback_location: tool_mails_path(@tool, folder: "trash"), notice: "Email restored."
      end

      # DELETE /tools/:tool_id/mails/trash (empty trash)
      def destroy_all
        count = @tool.mail_account.messages.trashed.destroy_all.count
        redirect_to tool_mails_path(@tool, folder: "trash"), notice: "#{count} email(s) permanently deleted."
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

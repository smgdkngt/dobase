# frozen_string_literal: true

module Tools
  module Chats
    class ReadsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def create
        @read_receipt = @tool.chat.mark_as_read_for!(current_user)

        respond_to do |format|
          format.any { head :ok }
          format.json { render :show }
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

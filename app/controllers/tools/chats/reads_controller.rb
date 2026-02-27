# frozen_string_literal: true

module Tools
  module Chats
    class ReadsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }

      def create
        @tool.chat.mark_as_read_for!(current_user)
        head :ok
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end
    end
  end
end

# frozen_string_literal: true

module Tools
  class ChatsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def show
      @chat = @tool.chat
      @messages = @chat.messages.chronological.includes(:user, files_attachments: :blob, reply_to: :user).last(100)
      @participants = @chat.participants
      @chat.mark_as_read_for!(current_user)
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end
  end
end

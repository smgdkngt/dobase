# frozen_string_literal: true

module Tools
  module Chats
    class MessagesController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message, only: %i[update destroy]

      def create
        @message = @tool.chat.messages.build(message_params)
        @message.user = current_user

        if @message.save
          head :ok
        else
          render turbo_stream: turbo_stream.replace(
            "chat-form-errors",
            partial: "shared/error_flash",
            locals: { object: @message }
          ), status: :unprocessable_entity
        end
      end

      def update
        unless @message.user == current_user
          head :forbidden
          return
        end

        if @message.update(body: params.dig(:message, :body), edited_at: Time.current)
          head :ok
        else
          render turbo_stream: turbo_stream.replace(
            "chat-form-errors",
            partial: "shared/error_flash",
            locals: { object: @message }
          ), status: :unprocessable_entity
        end
      end

      def destroy
        unless @message.user == current_user || @tool.owned_by?(current_user)
          head :forbidden
          return
        end

        @message.destroy
        head :ok
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.chat.messages.find(params[:id])
      end

      def message_params
        params.require(:message).permit(:body, :reply_to_id, files: [])
      end
    end
  end
end

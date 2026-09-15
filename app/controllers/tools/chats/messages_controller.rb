# frozen_string_literal: true

module Tools
  module Chats
    # The chat form submits through Turbo and new messages arrive over the chat's
    # broadcast, so the browser only gets a status or the form errors. Those use
    # format.any rather than format.html so the errors keep their Turbo Stream type.
    class MessagesController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_message, only: %i[update destroy]
      before_action :ensure_author, only: :update
      before_action :ensure_author_or_owner, only: :destroy

      def create
        @message = @tool.chat.messages.build(message_params)
        @message.user = current_user

        respond_to do |format|
          if @message.save
            format.any { head :ok }
            format.json { render :show, status: :created }
          else
            format.any { render_form_errors }
            format.json { render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def update
        respond_to do |format|
          if @message.update(body: params.dig(:message, :body), edited_at: Time.current)
            format.any { head :ok }
            format.json { render :show }
          else
            format.any { render_form_errors }
            format.json { render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        @message.destroy

        respond_to do |format|
          format.any { head :ok }
          format.json { head :no_content }
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_message
        @message = @tool.chat.messages.find(params[:id])
      end

      def ensure_author
        forbid "Only the author can edit this message" unless @message.user == current_user
      end

      def ensure_author_or_owner
        unless @message.user == current_user || @tool.owned_by?(current_user)
          forbid "Only the author or an owner can delete this message"
        end
      end

      def forbid(message)
        respond_to do |format|
          format.any { head :forbidden }
          format.json { render json: { error: message }, status: :forbidden }
        end
      end

      def message_params
        params.require(:message).permit(:body, :reply_to_id, files: [])
      end

      def render_form_errors
        render turbo_stream: turbo_stream.replace(
          "chat-form-errors",
          partial: "shared/error_flash",
          locals: { object: @message }
        ), status: :unprocessable_entity
      end
    end
  end
end

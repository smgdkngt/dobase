# frozen_string_literal: true

module Tools
  module Chats
    module Messages
      # Your emoji on a message: put it there, or take it off again. Everyone in
      # the chat gets the new row over the chat's broadcast, so the page needs
      # nothing back; the API gets the message with its reactions.
      class ReactionsController < ApplicationController
        include ToolScoped

        allow_access_tokens
        wrap_parameters false
        before_action :set_message

        def create
          @message.reactions.find_or_create_by!(user: current_user, emoji: params[:emoji])
          respond(status: :created)
        rescue ActiveRecord::RecordInvalid => e
          respond_to do |format|
            format.any { head :unprocessable_entity }
            format.json { render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity }
          end
        end

        def destroy
          @message.reactions.find_by(user: current_user, emoji: params[:emoji])&.destroy
          respond
        end

        private

        def set_message
          @message = @tool.chat.messages.find(params[:message_id])
        end

        def respond(status: :ok)
          respond_to do |format|
            format.any { head :no_content }
            format.json { render "tools/chats/messages/show", status: status }
          end
        end
      end
    end
  end
end

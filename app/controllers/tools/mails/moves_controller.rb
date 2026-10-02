# frozen_string_literal: true

module Tools
  module Mails
    class MovesController < ApplicationController
      include ToolScoped
      include NextMailNavigation

      allow_access_tokens
      before_action :set_message

      # POST /tools/:tool_id/mails/:mail_id/move
      def create
        # A folder the server has, whatever characters its name has there
        target_folder = @tool.mail_account.folder_to_move_to(params[:folder])

        unless target_folder
          respond_to do |format|
            format.html { redirect_back fallback_location: tool_mails_path(@tool), alert: "Invalid folder name." }
            format.json { render json: { errors: [ "Invalid folder name" ] }, status: :unprocessable_entity }
          end
          return
        end

        current_folder = params[:current_folder] || "inbox"
        next_msg = find_next_message(@message, current_folder)

        # A draft moves by itself: the conversation it answers stays where it is
        moving = @message.draft? ? [ @message ] : with_their_conversations([ @message ], folder: current_folder)
        moving.each { |message| message.move_to_folder!(target_folder) }

        respond_to do |format|
          format.html { redirect_to_next_mail_or_fallback(next_msg, folder: current_folder, notice: "Moved to #{helpers.mail_folder_name(target_folder)}.") }
          format.json { render "tools/mails/message" }
        end
      end

      private

      def set_message
        @message = ::Mails::Message.where(account: @tool.mail_account).find(params[:mail_id])
      end
    end
  end
end

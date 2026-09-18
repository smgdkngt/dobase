# frozen_string_literal: true

module Tools
  module Chats
    class ReadsController < ApplicationController
      include ToolScoped

      allow_access_tokens

      def create
        @read_receipt = @tool.chat.mark_as_read_for!(current_user)

        respond_to do |format|
          format.any { head :ok }
          format.json { render :show }
        end
      end
    end
  end
end

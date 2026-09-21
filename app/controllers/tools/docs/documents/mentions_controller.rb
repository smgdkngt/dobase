# frozen_string_literal: true

module Tools
  module Docs
    module Documents
      # Someone picked a colleague from the @-list while writing a document.
      #
      # A document is written by several people at once and saved by all of
      # them, so the text can't say who added a mention. The page where it was
      # picked says so instead, the moment it happens, and that person is the
      # one named in the notification.
      class MentionsController < ApplicationController
        include ToolScoped

        before_action :set_document

        # POST /tools/:tool_id/docs/documents/:document_id/mentions
        def create
          mentioned = @tool.notifiable_users.where.not(id: current_user.id).find_by(id: params[:user_id])

          if mentioned
            MentionNotifier.with(
              mentioner: current_user, tool: @tool, context: @document.title,
              url: tool_docs_document_path(@tool, @document)
            ).deliver(mentioned)
            mentioned.prune_notifications!
          end

          head :no_content
        end

        private

        def set_document
          @document = @tool.documents.find(params[:document_id])
        end
      end
    end
  end
end

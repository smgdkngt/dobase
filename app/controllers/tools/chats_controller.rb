# frozen_string_literal: true

module Tools
  class ChatsController < ApplicationController
    include ToolAuthorization

    MESSAGES_PER_PAGE = 50
    MAX_MESSAGES_PER_PAGE = 200

    allow_access_tokens

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def show
      @chat = @tool.chat

      respond_to do |format|
        format.html do
          @messages = @chat.messages.chronological.with_associations.last(100)
          @participants = @chat.participants
          @chat.mark_as_read_for!(current_user)
        end
        # Reading through the API leaves the chat unread; POST /tools/:tool_id/chat/read marks it read.
        format.json { set_page_of_messages }
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

    # The latest messages (before params[:before], when paging back), oldest first.
    def set_page_of_messages
      limit = (Integer(params[:limit], exception: false) || MESSAGES_PER_PAGE).clamp(1, MAX_MESSAGES_PER_PAGE)
      messages = @chat.messages.with_associations.recent
      messages = messages.before(@chat.messages.find(Integer(params[:before], exception: false))) if params[:before].present?

      page = messages.limit(limit + 1).to_a
      @has_more = page.size > limit
      @messages = page.first(limit).reverse
    end
  end
end

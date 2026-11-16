# frozen_string_literal: true

module Tools
  class ChatsController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      @chat = @tool.chat

      respond_to do |format|
        format.html do
          set_page_of_messages
          @participants = @chat.participants.with_attached_avatar.to_a
          @chat.mark_as_read_for!(current_user)
          current_user.read_notifications_about!(records: [ @tool ], urls: [ tool_chat_path(@tool) ],
            types: %w[ChatMessageNotifier MentionNotifier])
        end
        # Reading through the API leaves the chat unread; POST /tools/:tool_id/chat/read marks it read.
        format.json { set_page_of_messages }
      end
    end

    private

    # The latest messages (before params[:before], when paging back), oldest first. With
    # params[:message], the messages around that one: what a mention or a search hit
    # leads to. A message that is gone (or another chat's) is the chat as it is now.
    def set_page_of_messages
      @focus = @chat.messages.with_associations.find_by(id: params[:message]) if params[:message].present?

      if @focus
        @messages, @has_more, @has_newer = @chat.page_around(@focus)
      else
        limit = (Integer(params[:limit], exception: false) || ::Chats::Chat::MESSAGES_PER_PAGE)
          .clamp(1, ::Chats::Chat::MAX_MESSAGES_PER_PAGE)

        @messages, @has_more = @chat.page_of_messages(before: params[:before], limit: limit)
        @has_newer = false
      end
    end
  end
end

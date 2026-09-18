# frozen_string_literal: true

module Tools
  module Chats
    # The chat form submits through Turbo and new messages arrive over the chat's
    # broadcast, so the browser only needs the error slot updated — cleared on
    # success, filled in on failure. Those use format.any rather than format.html
    # so the response keeps its Turbo Stream type.
    class MessagesController < ApplicationController
      include ToolScoped

      # index pages the page itself back through the chat and answers a turbo
      # stream; the API reads the chat's own JSON, which already pages.
      allow_access_tokens except: %i[index edit]
      before_action :set_message, only: %i[show edit update destroy]
      before_action :ensure_author, only: %i[edit update]
      before_action :ensure_author_or_owner, only: :destroy

      # The page back through the chat: the messages just before params[:before]
      # go in above the ones already on the page, and the "load older" trigger
      # is replaced with one that asks for the page before this one.
      def index
        @chat = @tool.chat
        @messages, @has_more = @chat.page_of_messages(before: params[:before])

        render turbo_stream: [
          # The page already opens with this day's separator, above the message
          # this page ends at. The prepended page brings its own, in the right
          # place, so the old one goes first — removing it afterwards would take
          # the new one instead, since they share an id.
          remove_boundary_date_separator,
          turbo_stream.prepend("chat_messages", partial: "tools/chats/messages", locals: { messages: @messages }),
          fold_boundary_message_into_its_group,
          turbo_stream.replace("chat_older_messages", partial: "tools/chats/older_messages",
            locals: { tool: @tool, messages: @messages, has_more: @has_more })
        ].compact
      end

      # The message's own body, which is also how cancelling an edit puts the
      # text back where the form was.
      def show
      end

      # The form that takes the place of the body, for its author.
      def edit
      end

      def create
        @message = @tool.chat.messages.build(message_params)
        @message.user = current_user

        respond_to do |format|
          if @message.save
            format.any { render_message_errors }
            format.json { render :show, status: :created }
          else
            format.any { render_message_errors(status: :unprocessable_entity) }
            format.json { render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def update
        respond_to do |format|
          if @message.update(edit_params.merge(edited_at: Time.current))
            # The message is broadcast to everyone in the chat, but the person
            # who edited it gets it back in the response too: their form has to
            # give way to the rewritten message even if the broadcast doesn't
            # reach them.
            format.any { render_message_errors(extra: turbo_stream.replace(@message, partial: "tools/chats/message", locals: { message: @message })) }
            format.json { render :show }
          else
            format.any { render_message_errors(status: :unprocessable_entity) }
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

      # The message the page opened with was the first of its group, so it drew
      # its author's name and avatar. Now that the message before it is on the
      # page too, it may belong to that group after all, and is drawn again as
      # the continuation it is.
      def fold_boundary_message_into_its_group
        previous = @messages.last
        boundary = @tool.chat.messages.find_by(id: params[:before])
        return unless previous && boundary && helpers.chat_continuation?(previous, boundary)

        turbo_stream.replace(boundary, partial: "tools/chats/message",
          locals: { message: boundary, is_continuation: true })
      end

      def remove_boundary_date_separator
        date = @messages.last&.created_at&.to_date
        turbo_stream.remove("chat_date_#{date}") if date
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

      # Only the body can be edited, and only when it's actually in the request:
      # reading params[:message][:body] straight through blanked the text of any
      # message whose update didn't mention it (a files-only message survives a
      # blank body, so nothing caught it).
      def edit_params
        params.require(:message).permit(:body)
      end

      # Updates the error slot's contents with the message's current errors —
      # none on success, which is what clears a previous failed attempt's
      # message instead of leaving it stuck once the next send goes through.
      # turbo_stream.update (not replace): shared/error_flash renders no
      # element with the "chat-form-errors" id itself (just a bare .flash
      # div, or nothing), so a replace would remove the slot from the page —
      # leaving nothing for a later failed send to target.
      def render_message_errors(status: :ok, extra: nil)
        errors = turbo_stream.update(
          "chat-form-errors",
          partial: "shared/error_flash",
          locals: { object: @message }
        )

        render turbo_stream: [ errors, extra ].compact, status: status
      end
    end
  end
end

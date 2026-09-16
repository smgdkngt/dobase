# frozen_string_literal: true

class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat = Chats::Chat.find_by(id: params[:chat_id])
    reject and return unless chat&.tool&.accessible_by?(current_user)

    @chat = chat
    stream_for @chat
    transmit({ type: "welcome", user_id: current_user.id })
    broadcast_presence("online", hello: true)
  end

  # Someone who just (re)connected says hello; everyone else in the chat answers with
  # announce_presence, so both sides know who's online
  def request_presence
    broadcast_presence("online", hello: true) if @chat
  end

  def announce_presence
    broadcast_presence("online") if @chat
  end

  def unsubscribed
    return unless @chat

    stop_typing
    broadcast_presence("offline")
  end

  def typing
    return unless @chat

    ChatChannel.broadcast_to(
      @chat,
      {
        type: "typing",
        user_id: current_user.id,
        user_name: current_user.name
      }
    )
  end

  def stop_typing
    return unless @chat

    ChatChannel.broadcast_to(
      @chat,
      {
        type: "stop_typing",
        user_id: current_user.id
      }
    )
  end

  private

  def broadcast_presence(status, hello: false)
    ChatChannel.broadcast_to(
      @chat,
      {
        type: "presence",
        user_id: current_user.id,
        user_name: current_user.name,
        status: status,
        hello: hello
      }
    )
  end
end

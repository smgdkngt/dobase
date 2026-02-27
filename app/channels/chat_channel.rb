# frozen_string_literal: true

class ChatChannel < ApplicationCable::Channel
  def subscribed
    @chat = Chats::Chat.find(params[:chat_id])
    reject unless @chat.tool.accessible_by?(current_user)
    stream_for @chat

    # Broadcast user came online (with small delay to ensure subscription is ready)
    transmit({ type: "welcome", user_id: current_user.id })
    broadcast_presence("online")
  end

  # Allow clients to request current online users
  def request_presence
    broadcast_presence("online")
  end

  def unsubscribed
    return unless @chat

    stop_typing
    broadcast_presence("offline")
  end

  def typing
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

  def broadcast_presence(status)
    ChatChannel.broadcast_to(
      @chat,
      {
        type: "presence",
        user_id: current_user.id,
        user_name: current_user.name,
        status: status
      }
    )
  end
end

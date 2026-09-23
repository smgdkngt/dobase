# frozen_string_literal: true

class ChatChannel < ApplicationCable::Channel
  # "Anna is typing": pages show it for a few seconds unless they hear it again
  def self.typing(chat, user)
    broadcast_to(chat, { type: "typing", user_id: user.id, user_name: user.name })
  end

  def self.stop_typing(chat, user)
    broadcast_to(chat, { type: "stop_typing", user_id: user.id })
  end

  def subscribed
    chat = Chats::Chat.find_by(id: params[:chat_id])
    reject and return unless chat&.tool&.accessible_by?(current_user)

    @chat = chat
    ChatPresence.connect(@chat.id, current_user.id)
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

  # One tab closing doesn't mean the person left: only the last connection to go
  # takes them offline (and stops any typing indicator they left behind).
  def unsubscribed
    return unless @chat
    return unless ChatPresence.disconnect(@chat.id, current_user.id)

    stop_typing
    broadcast_presence("offline")
  end

  def typing
    ChatChannel.typing(@chat, current_user) if @chat
  end

  def stop_typing
    ChatChannel.stop_typing(@chat, current_user) if @chat
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

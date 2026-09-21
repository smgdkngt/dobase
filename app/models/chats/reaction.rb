# frozen_string_literal: true

module Chats
  # An emoji someone put on a chat message. One of a short, fixed set, so a
  # reaction is a quick answer rather than another message, and each person
  # puts each emoji on a message once.
  class Reaction < ApplicationRecord
    self.table_name = "chat_reactions"

    EMOJI = %w[👍 ❤️ 😂 🎉 😮 🙏 👀 ✅].freeze

    belongs_to :message, class_name: "Chats::Message"
    belongs_to :user

    validates :emoji, inclusion: { in: EMOJI }
    validates :emoji, uniqueness: { scope: %i[message_id user_id] }

    # Everyone in the chat sees the new count; the row is redrawn, not the
    # message, so a message that continues its author's group stays one. It's
    # drawn from the message as stored now: this reaction's copy of the message
    # may remember an older list of reactions.
    after_commit -> {
      current = Chats::Message.includes(reactions: :user).find_by(id: message_id)
      next unless current

      broadcast_replace_to current.chat,
        target: ActionView::RecordIdentifier.dom_id(current, :reactions),
        partial: "tools/chats/reactions",
        locals: { message: current }
    }, on: %i[create destroy]
  end
end

# frozen_string_literal: true

module Chats
  class Chat < ApplicationRecord
    self.table_name = "chats"

    belongs_to :tool
    has_many :read_receipts, class_name: "Chats::ReadReceipt", foreign_key: "chat_id", dependent: :destroy
    has_many :messages, class_name: "Chats::Message", foreign_key: "chat_id", dependent: :destroy

    validates :tool_id, uniqueness: { message: "already has a chat" }

    def participants
      User.where(id: tool.collaborators.select(:user_id))
    end

    def unread_count_for(user)
      receipt = read_receipts.find_by(user: user)
      return messages.count if receipt.nil?

      messages.where("created_at > ?", receipt.last_read_at).count
    end

    def mark_as_read_for!(user)
      last_message = messages.order(created_at: :desc).first
      receipt = read_receipts.find_or_initialize_by(user: user)
      receipt.update!(
        last_read_message: last_message,
        last_read_at: Time.current
      )
    end
  end
end

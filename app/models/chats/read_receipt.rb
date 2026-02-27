# frozen_string_literal: true

module Chats
  class ReadReceipt < ApplicationRecord
    self.table_name = "chat_read_receipts"

    belongs_to :chat, class_name: "Chats::Chat"
    belongs_to :user
    belongs_to :last_read_message, class_name: "Chats::Message", optional: true

    validates :user_id, uniqueness: { scope: :chat_id, message: "already has a read receipt for this chat" }
  end
end

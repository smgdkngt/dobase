# frozen_string_literal: true

module Chats
  class Chat < ApplicationRecord
    self.table_name = "chats"

    MESSAGES_PER_PAGE = 50
    MAX_MESSAGES_PER_PAGE = 200

    belongs_to :tool
    has_many :read_receipts, class_name: "Chats::ReadReceipt", foreign_key: "chat_id", dependent: :destroy
    has_many :messages, class_name: "Chats::Message", foreign_key: "chat_id", dependent: :destroy

    validates :tool_id, uniqueness: { message: "already has a chat" }

    # A page of messages, oldest first: the latest ones, or the ones just before
    # message id `before` when paging back. Answers the page and whether there
    # are older messages still. The page and the JSON API read the same method.
    def page_of_messages(before: nil, limit: MESSAGES_PER_PAGE)
      scope = messages.with_associations.recent
      scope = scope.before(messages.find(Integer(before, exception: false))) if before.present?

      page = scope.limit(limit + 1).to_a
      [ page.first(limit).reverse, page.size > limit ]
    end

    def participants
      User.where(id: tool.collaborators.select(:user_id))
    end

    # Your own messages are never unread for you.
    def unread_count_for(user)
      from_others = messages.where.not(user_id: user.id)
      receipt = read_receipts.find_by(user: user)
      return from_others.count if receipt.nil?

      from_others.where("chat_messages.created_at > ?", receipt.last_read_at).count
    end

    def mark_as_read_for!(user)
      last_message = messages.order(created_at: :desc).first
      read_receipts.find_or_initialize_by(user: user).tap do |receipt|
        receipt.update!(
          last_read_message: last_message,
          last_read_at: Time.current
        )
      end
    end
  end
end

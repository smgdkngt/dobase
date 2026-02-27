# frozen_string_literal: true

module Boards
  class Comment < ApplicationRecord
    self.table_name = "comments"

    belongs_to :card, class_name: "Boards::Card"
    belongs_to :user

    has_rich_text :body

    validates :body, presence: true

    after_create_commit :notify_collaborators

    private

    def notify_collaborators
      tool = card.column.board.tool
      recipients = tool.users.where.not(id: user_id)
      return if recipients.none?

      CardCommentNotifier.with(comment: self, commenter: user, card: card, tool: tool).deliver(recipients)
      recipients.each(&:prune_notifications!)
    end
  end
end

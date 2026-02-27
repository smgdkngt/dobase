# frozen_string_literal: true

module Todos
  class Comment < ApplicationRecord
    self.table_name = "todo_comments"

    belongs_to :item, class_name: "Todos::Item", foreign_key: :todo_item_id
    belongs_to :user

    has_rich_text :body

    validates :body, presence: true

    after_create_commit :notify_collaborators

    private

    def notify_collaborators
      tool = item.list.tool
      recipients = tool.users.where.not(id: user_id)
      return if recipients.none?

      TodoCommentNotifier.with(comment: self, commenter: user, item: item, tool: tool).deliver(recipients)
      recipients.each(&:prune_notifications!)
    end
  end
end

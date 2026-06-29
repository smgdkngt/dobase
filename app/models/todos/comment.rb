# frozen_string_literal: true

module Todos
  class Comment < ApplicationRecord
    self.table_name = "todo_comments"

    include Mentionable

    belongs_to :item, class_name: "Todos::Item", foreign_key: :todo_item_id
    belongs_to :user

    has_rich_text :body

    validates :body, presence: true

    after_create_commit :notify_collaborators

    private

    def notify_collaborators
      tool = item.list.tool
      audience = tool.notifiable_users.where.not(id: user_id)
      return if audience.none?

      mentioned = mentioned_users_in(tool, excluding: user).to_a
      mentioned_ids = mentioned.map(&:id)

      generic = audience.where.not(id: mentioned_ids)
      TodoCommentNotifier.with(comment: self, commenter: user, item: item, tool: tool).deliver(generic) if generic.exists?

      if mentioned.any?
        MentionNotifier.with(
          mentioner: user, tool: tool, context: "a comment on #{item.title}",
          url: Rails.application.routes.url_helpers.tool_todo_path(tool, item: item.id)
        ).deliver(mentioned)
      end

      audience.each(&:prune_notifications!)
    end
  end
end

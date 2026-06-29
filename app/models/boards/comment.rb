# frozen_string_literal: true

module Boards
  class Comment < ApplicationRecord
    self.table_name = "comments"

    include Mentionable

    belongs_to :card, class_name: "Boards::Card"
    belongs_to :user

    has_rich_text :body

    validates :body, presence: true

    after_create_commit :notify_collaborators

    private

    def notify_collaborators
      tool = card.column.board.tool
      audience = tool.notifiable_users.where.not(id: user_id)
      return if audience.none?

      mentioned = mentioned_users_in(tool, excluding: user).to_a
      mentioned_ids = mentioned.map(&:id)

      generic = audience.where.not(id: mentioned_ids)
      CardCommentNotifier.with(comment: self, commenter: user, card: card, tool: tool).deliver(generic) if generic.exists?

      if mentioned.any?
        MentionNotifier.with(
          mentioner: user, tool: tool, context: "a comment on #{card.title}",
          url: Rails.application.routes.url_helpers.tool_board_path(tool, card: card.id)
        ).deliver(mentioned)
      end

      audience.each(&:prune_notifications!)
    end
  end
end

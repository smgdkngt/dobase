# frozen_string_literal: true

module Boards
  class Comment < ApplicationRecord
    self.table_name = "comments"

    include Mentionable
    include PostedVia

    belongs_to :card, class_name: "Boards::Card"
    # Kept when the author deletes their account (the column is nullified)
    belongs_to :user, optional: true
    validates :user, presence: true, on: :create

    has_rich_text :body

    validates :body, presence: true

    after_create_commit :notify_collaborators
    after_create_commit { card.record_event(:commented, comment_id: id, excerpt: Event.excerpt(body.to_plain_text)) }

    private

    def notify_collaborators
      tool = card.column.board.tool
      audience = notification_audience(tool)
      return if audience.none?

      mentioned = mentioned_users_in(tool, excluding: author_to_skip).to_a
      mentioned_ids = mentioned.map(&:id)

      generic = audience.where.not(id: mentioned_ids)
      CardCommentNotifier.with(comment: self, commenter: user, card: card, tool: tool).deliver(generic) if generic.exists?

      if mentioned.any?
        MentionNotifier.with(
          mentioner: user, byline: (byline if agent?), tool: tool, context: "a comment on #{card.title}",
          url: Rails.application.routes.url_helpers.tool_board_path(tool, card: card.id)
        ).deliver(mentioned)
      end

      audience.each(&:prune_notifications!)
    end
  end
end

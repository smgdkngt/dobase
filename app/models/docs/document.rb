# frozen_string_literal: true

module Docs
  class Document < ApplicationRecord
    self.table_name = "documents"

    belongs_to :tool
    belongs_to :last_edited_by, class_name: "User", optional: true
    belongs_to :locked_by, class_name: "User", optional: true

    has_rich_text :content

    validates :title, presence: true

    scope :ordered, -> { order(updated_at: :desc) }

    # Lock expires after 5 minutes of inactivity
    LOCK_TIMEOUT = 5.minutes

    def locked?
      locked_by_id.present? && locked_at.present? && locked_at > LOCK_TIMEOUT.ago
    end

    def preview_text(length: 200)
      return "" if content.blank?

      content.to_plain_text.squish.truncate(length)
    end

    def broadcast_content_update
      DocumentChannel.broadcast_to(self, {
        type: "content_updated",
        title: title,
        content_html: content.to_s,
        edited_by: last_edited_by&.name,
        edited_at: "just now"
      })
    end
  end
end

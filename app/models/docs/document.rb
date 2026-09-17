# frozen_string_literal: true

module Docs
  class Document < ApplicationRecord
    include Trackable
    self.table_name = "documents"

    belongs_to :tool
    belongs_to :locked_by, class_name: "User", optional: true

    has_rich_text :content

    validates :title, presence: true

    # Most recently edited first, by the time the documents list shows (edited_at)
    scope :ordered, -> { order(Arel::Nodes::NamedFunction.new("COALESCE", [ arel_table[:last_edited_at], arel_table[:updated_at] ]).desc, id: :desc) }

    # Lock expires after 5 minutes of inactivity
    LOCK_TIMEOUT = 5.minutes

    def locked?
      locked_by_id.present? && locked_at.present? && locked_at > LOCK_TIMEOUT.ago
    end

    # When the content was last changed. Taking the edit lock touches updated_at too.
    def edited_at
      last_edited_at || updated_at
    end

    def preview_text(length: 200)
      return "" if content.blank?

      content.to_plain_text.squish.truncate(length)
    end

    # HTML preview for grid cards — truncates to a safe length and replaces
    # <a> tags with <span> to avoid invalid nested links inside link_to blocks.
    # Loofah (Rails dependency) closes any tags broken by the truncation.
    def preview_html
      return "" if content.body.blank?

      html = content.body.to_s.gsub(%r{<a\b[^>]*>}i, "<span>").gsub(%r{</a>}i, "</span>")
      Loofah.fragment(html[0, 1500]).to_s.html_safe
    end

    def broadcast_content_update
      DocumentChannel.broadcast_to(self, {
        type: "content_updated",
        title: title,
        content_html: content.to_s,
        edited_by: updated_by&.name,
        edited_at: "just now"
      })
    end
  end
end

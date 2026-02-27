# frozen_string_literal: true

module Todos
  class Item < ApplicationRecord
    self.table_name = "todo_items"

    belongs_to :list, class_name: "Todos::List", foreign_key: :todo_list_id
    belongs_to :assigned_user, class_name: "User", optional: true
    has_many :comments, class_name: "Todos::Comment", foreign_key: :todo_item_id, dependent: :destroy
    has_many :attachments, class_name: "Todos::Attachment", foreign_key: :todo_item_id, dependent: :destroy
    has_rich_text :description

    validates :title, presence: true

    scope :pending, -> { where(completed_at: nil) }
    scope :recently_completed, -> { where(completed_at: 24.hours.ago..) }
    scope :completed_hidden, -> { where(completed_at: ...24.hours.ago) }
    scope :visible, -> { pending.or(recently_completed) }

    def completed? = completed_at.present?
  end
end

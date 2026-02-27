# frozen_string_literal: true

module Todos
  class Attachment < ApplicationRecord
    include HumanFileSize

    self.table_name = "todo_item_attachments"

    belongs_to :item, class_name: "Todos::Item", foreign_key: :todo_item_id
    has_one_attached :file

    MAX_FILE_SIZE = 25.megabytes

    validates :filename, presence: true
    validate :file_size_within_limit

    alias_method :human_readable_size, :human_file_size

    private

    def file_size_within_limit
      errors.add(:file, "is too large (max 25 MB)") if file_size.present? && file_size > MAX_FILE_SIZE
    end
  end
end

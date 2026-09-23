# frozen_string_literal: true

module Boards
  class Attachment < ApplicationRecord
    include HumanFileSize
    include BlockedFileType

    self.table_name = "card_attachments"

    belongs_to :card, class_name: "Boards::Card"
    has_one_attached :file

    MAX_FILE_SIZE = 25.megabytes

    validates :filename, presence: true
    validate :file_size_within_limit

    alias_method :human_readable_size, :human_file_size

    private

    def file_size_within_limit
      limit = Demo.upload_limit(MAX_FILE_SIZE)
      errors.add(:file, "is too large (max #{limit / 1.megabyte} MB)") if file_size.present? && file_size > limit
    end
  end
end

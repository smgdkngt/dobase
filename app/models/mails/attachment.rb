# frozen_string_literal: true

module Mails
  class Attachment < ApplicationRecord
    include HumanFileSize

    self.table_name = "mail_attachments"

    belongs_to :message, class_name: "Mails::Message", foreign_key: "mail_message_id"
    has_one_attached :file

    validates :filename, presence: true

    alias_method :human_readable_size, :human_file_size

    # The pictures a mail can show in its text: the ones sanitizing lets through as data: URLs
    INLINE_IMAGE_TYPES = %w[image/png image/jpeg image/gif].freeze

    # Whether this is the picture an <img src="cid:..."> in its message shows. Mail saved
    # before Content-IDs were kept goes by the file name, which Outlook starts the ID with.
    def content_id?(id)
      return false unless content_type.in?(INLINE_IMAGE_TYPES)

      content_id.present? ? content_id.casecmp?(id) : filename.casecmp?(id.split("@").first.to_s)
    end
  end
end

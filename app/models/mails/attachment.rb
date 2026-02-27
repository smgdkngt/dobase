# frozen_string_literal: true

module Mails
  class Attachment < ApplicationRecord
    include HumanFileSize

    self.table_name = "mail_attachments"

    belongs_to :message, class_name: "Mails::Message", foreign_key: "mail_message_id"
    has_one_attached :file

    validates :filename, presence: true

    alias_method :human_readable_size, :human_file_size
  end
end

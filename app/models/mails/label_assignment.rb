# frozen_string_literal: true

module Mails
  class LabelAssignment < ApplicationRecord
    self.table_name = "mail_label_assignments"

    belongs_to :message, class_name: "Mails::Message", foreign_key: "mail_message_id"
    belongs_to :label, class_name: "Mails::Label", foreign_key: "mail_label_id"

    validates :mail_message_id, uniqueness: { scope: :mail_label_id }
  end
end

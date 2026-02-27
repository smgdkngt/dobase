# frozen_string_literal: true

module Mails
  class Label < ApplicationRecord
    self.table_name = "mail_labels"

    DEFAULT_COLORS = %w[
      #ef4444 #f97316 #eab308 #22c55e #14b8a6
      #3b82f6 #8b5cf6 #ec4899 #6b7280
    ].freeze

    belongs_to :account, class_name: "Mails::Account", foreign_key: "mail_account_id"
    has_many :label_assignments, class_name: "Mails::LabelAssignment", foreign_key: "mail_label_id", dependent: :destroy
    has_many :messages, through: :label_assignments

    validates :name, presence: true, uniqueness: { scope: :mail_account_id }
  end
end

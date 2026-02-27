# frozen_string_literal: true

module Mails
  class Contact < ApplicationRecord
    self.table_name = "mail_contacts"

    belongs_to :account, class_name: "Mails::Account", foreign_key: "mail_account_id"

    validates :email_address, presence: true, uniqueness: { scope: :mail_account_id }

    scope :search, ->(query) {
      where("name LIKE :q OR email_address LIKE :q", q: "%#{query}%")
    }

    scope :most_contacted, -> { order(times_contacted: :desc) }
  end
end

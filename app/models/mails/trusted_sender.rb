# frozen_string_literal: true

module Mails
  # A sender whose mail shows its images without asking first
  class TrustedSender < ApplicationRecord
    self.table_name = "mail_trusted_senders"

    belongs_to :account, class_name: "Mails::Account", foreign_key: "mail_account_id"

    normalizes :email_address, with: ->(address) { address.strip.downcase }

    validates :email_address, presence: true, uniqueness: { scope: :mail_account_id }
  end
end

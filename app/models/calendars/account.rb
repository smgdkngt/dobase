# frozen_string_literal: true

module Calendars
  class Account < ApplicationRecord
    include EncryptedPassword

    self.table_name = "calendar_accounts"

    belongs_to :tool
    has_many :calendars, class_name: "Calendars::Calendar", foreign_key: "calendar_account_id", dependent: :destroy
    has_many :events, through: :calendars

    accepts_nested_attributes_for :calendars

    validates :username, presence: true
    validates :encrypted_password, presence: true

    PROVIDERS = %w[fastmail icloud nextcloud google custom].freeze

    private

    def encryption_salt
      "calendar account password"
    end
  end
end

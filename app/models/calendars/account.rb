# frozen_string_literal: true

module Calendars
  class Account < ApplicationRecord
    include EncryptedPassword

    self.table_name = "calendar_accounts"

    belongs_to :tool
    has_many :calendars, class_name: "Calendars::Calendar", foreign_key: "calendar_account_id", dependent: :destroy
    has_many :events, through: :calendars

    accepts_nested_attributes_for :calendars

    normalizes :caldav_url, with: ->(url) { url.strip }
    # Only when set, so an account saved before this check can still record how its syncs went
    with_options unless: :local?, if: -> { new_record? || will_save_change_to_caldav_url? } do
      validates :caldav_url, presence: true
      validate :caldav_url_is_a_web_address
    end
    validates :username, presence: true, unless: :local?
    validates :encrypted_password, presence: true, unless: :local?

    PROVIDERS = %w[fastmail icloud nextcloud google custom local].freeze

    def local?
      provider == "local"
    end

    private

    def caldav_url_is_a_web_address
      return if caldav_url.blank?

      uri = URI.parse(caldav_url)
      errors.add(:caldav_url, "must be an http:// or https:// address") unless uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(:caldav_url, "must be an http:// or https:// address")
    end

    def encryption_salt
      "calendar account password"
    end
  end
end

# frozen_string_literal: true

module Oauth
  # One `dobase login` waiting for its person (RFC 8628). The CLI holds the
  # device code (kept here as a digest) and asks every few seconds; the person
  # types the user code in a browser where they are signed in and says yes or
  # no. A yes makes the connection once, for the first poll after it.
  class DeviceCode < ApplicationRecord
    self.table_name = "oauth_device_codes"

    LIFETIME = 10.minutes
    INTERVAL = 5
    # No vowels and nothing that reads as another letter: no words, no mix-ups
    ALPHABET = "BCDFGHJKLMNPQRSTVWXZ".chars.freeze
    STATUSES = %w[pending approved denied used].freeze

    belongs_to :client, class_name: "Oauth::Client", foreign_key: :oauth_client_id
    belongs_to :user, optional: true

    validates :status, inclusion: { in: STATUSES }
    validates :permission, inclusion: { in: AccessToken::PERMISSIONS }

    # Returns the record and the plain device code
    def self.issue(client)
      device_code = Oauth.secret
      record = create!(client:, device_code_digest: Oauth.digest(device_code), user_code: new_user_code,
        expires_at: LIFETIME.from_now)
      [ record, device_code ]
    end

    def self.new_user_code
      loop do
        code = Array.new(8) { ALPHABET.sample(random: SecureRandom) }.join.insert(4, "-")
        return code unless exists?(user_code: code)
      end
    end

    # What someone typed: case, spaces and the dash don't matter
    def self.waiting(user_code)
      letters = user_code.to_s.upcase.gsub(/[^A-Z]/, "")
      return if letters.length != 8

      where(status: "pending", expires_at: Time.current..).find_by(user_code: letters.insert(4, "-"))
    end

    # The CLI's poll: an error code as RFC 8628 names it, or the connection
    def self.poll(device_code, client:)
      record = find_by(device_code_digest: Oauth.digest(device_code.to_s)) if device_code.present?
      return "invalid_grant" if record.nil? || record.client != client

      record.with_lock { record.answer_poll }
    end

    def approve(user, permission:, agent:)
      update!(user:, permission:, agent:, status: "approved")
    end

    def deny
      update!(status: "denied")
    end

    def answer_poll
      return "expired_token" if expires_at.past?
      return "access_denied" if status == "denied"
      return "invalid_grant" if status == "used"

      too_fast = polled_at && polled_at > (INTERVAL - 1).seconds.ago
      update!(polled_at: Time.current)
      return "slow_down" if too_fast
      return "authorization_pending" if status == "pending"
      return "access_denied" unless user.mcp_enabled?

      update!(status: "used")
      user.access_tokens.create!(name: client.name, permission:, agent:, oauth_client: client, renews: true,
        expires_at: AccessToken::CONNECTION_LIFETIME.from_now)
    end
  end
end

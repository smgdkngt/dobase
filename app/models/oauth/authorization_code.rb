# frozen_string_literal: true

module Oauth
  # What the consent page hands the client, to be exchanged once for tokens
  # within a minute. Only its digest is kept. A code that comes back after it
  # was used was copied: the connection it made is ended.
  class AuthorizationCode < ApplicationRecord
    self.table_name = "oauth_authorization_codes"

    LIFETIME = 1.minute

    belongs_to :client, class_name: "Oauth::Client", foreign_key: :oauth_client_id, inverse_of: :authorization_codes
    belongs_to :user
    belongs_to :access_token, optional: true

    validates :permission, inclusion: { in: AccessToken::PERMISSIONS }

    # Returns the record and the plain code
    def self.issue(client:, user:, redirect_uri:, code_challenge:, permission:, agent:)
      code = Oauth.secret
      record = create!(client:, user:, redirect_uri:, code_challenge:, permission:, agent:,
        code_digest: Oauth.digest(code), expires_at: LIFETIME.from_now)
      [ record, code ]
    end

    # The connection for a code, its redirect and its PKCE verifier, or nil
    def self.exchange(code, client:, redirect_uri:, code_verifier:)
      record = find_by(code_digest: Oauth.digest(code.to_s)) if code.present?
      return if record.nil? || record.client != client

      reused = false
      record.with_lock do
        reused = record.used_at.present?
        record.update!(used_at: Time.current) unless reused
      end
      if reused
        record.access_token&.destroy
        return
      end
      return if record.expires_at.past? || record.redirect_uri != redirect_uri.to_s
      return unless Oauth.pkce_matches?(code_verifier, record.code_challenge)

      record.connect
    end

    def connect
      return unless user.mcp_enabled?

      user.access_tokens.create!(
        name: client.name, permission:, agent:, oauth_client: client, expires_at: AccessToken::CONNECTION_LIFETIME.from_now
      ).tap { |connection| update!(access_token: connection) }
    end
  end
end

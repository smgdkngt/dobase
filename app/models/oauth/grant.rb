# frozen_string_literal: true

module Oauth
  # A pair of tokens an OAuth client sends: an access token that lasts an hour
  # and a refresh token that gets the next pair. Both are kept as digests. All
  # pairs of one connection share its end date, however often they are
  # refreshed, except a login by code (the CLI), whose end moves on with every
  # refresh, so a machine in use stays signed in and one left alone runs out.
  # A refresh token used a second time can only be a copy in someone else's
  # hands, and ends the whole connection.
  class Grant < ApplicationRecord
    self.table_name = "oauth_grants"

    LIFETIME = 1.hour

    belongs_to :access_token

    scope :active, -> { where(revoked_at: nil) }

    # Returns the record and the two plain secrets
    def self.issue(access_token)
      access = AccessToken::PREFIX + Oauth.secret
      refresh = Oauth.secret
      record = create!(access_token:, token_digest: Oauth.digest(access), refresh_token_digest: Oauth.digest(refresh),
        expires_at: [ LIFETIME.from_now, access_token.expires_at ].compact.min)
      [ record, access, refresh ]
    end

    def self.authenticate(access)
      active.where(expires_at: Time.current..).find_by(token_digest: Oauth.digest(access))&.access_token
    end

    # A fresh pair for a refresh token of this client, or nil
    def self.refresh(refresh, client:)
      record = find_by(refresh_token_digest: Oauth.digest(refresh.to_s)) if refresh.present?
      return if record.nil? || record.access_token.oauth_client != client

      reused = false
      record.with_lock do
        reused = record.revoked_at.present?
        record.update!(revoked_at: Time.current) unless reused
      end
      connection = record.access_token
      if reused
        connection.destroy
        return
      end
      return if connection.expired? || !connection.user.mcp_enabled?

      connection.update!(expires_at: AccessToken::CONNECTION_LIFETIME.from_now) if connection.renews?
      issue(connection)
    end

    # RFC 7009: either token of a pair ends the connection it belongs to
    def self.revoke(token, client:)
      digest = Oauth.digest(token.to_s)
      record = find_by(token_digest: digest) || find_by(refresh_token_digest: digest)
      record.access_token.destroy if record && record.access_token.oauth_client == client
    end
  end
end

# frozen_string_literal: true

module Oauth
  # A program that registered itself (RFC 7591) to ask people for a connection.
  # Anyone may register one, so a client is worth nothing until someone says yes
  # to it, and one nobody said yes to is cleared away after a day.
  class Client < ApplicationRecord
    self.table_name = "oauth_clients"

    MAX_REDIRECT_URIS = 5
    UNUSED_LIFETIME = 1.day

    has_many :access_tokens, foreign_key: :oauth_client_id, inverse_of: :oauth_client, dependent: :destroy
    has_many :authorization_codes, foreign_key: :oauth_client_id, inverse_of: :client, dependent: :delete_all

    validates :uid, presence: true, uniqueness: true
    validates :name, presence: true, length: { maximum: 100 }
    validate :redirect_uris_allowed

    before_validation :generate_uid, on: :create

    scope :unused, -> { where.missing(:access_tokens).where(created_at: ...UNUSED_LIFETIME.ago) }

    def self.register(name:, redirect_uris:)
      create(name: name.to_s.squish.truncate(100).presence || "MCP client", redirect_uris: Array(redirect_uris).map(&:to_s))
    end

    def redirect_uri?(uri)
      redirect_uris.include?(uri.to_s)
    end

    def touch_last_used
      update_column(:last_used_at, Time.current) if last_used_at.nil? || last_used_at < 1.minute.ago
    end

    private

    def generate_uid
      self.uid ||= SecureRandom.uuid
    end

    def redirect_uris_allowed
      uris = redirect_uris
      if !uris.is_a?(Array) || uris.empty? || uris.size > MAX_REDIRECT_URIS
        errors.add(:redirect_uris, "must list between 1 and #{MAX_REDIRECT_URIS} addresses")
      elsif uris.any? { |uri| !uri.is_a?(String) || uri.length > 500 || !Oauth.allowed_redirect?(uri) }
        errors.add(:redirect_uris, "may only lead to Claude or to this computer")
      end
    end
  end
end

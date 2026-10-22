# frozen_string_literal: true

# OAuth 2.1 for MCP clients: Claude (claude.ai, Claude Code) and the dobase CLI
# register themselves, a person says yes on the consent page, and the client
# gets short-lived tokens for `/mcp` and the JSON API. PKCE with S256 only, no
# client secrets (every client is public), redirects only to Claude's own
# addresses and to this machine.
module Oauth
  # Where a registered client may send someone back to after consent
  REDIRECT_HOSTS = %w[claude.ai claude.com].freeze
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze

  def self.digest(secret)
    OpenSSL::Digest::SHA256.hexdigest(secret)
  end

  def self.secret
    SecureRandom.urlsafe_base64(32)
  end

  def self.allowed_redirect?(uri)
    parsed = URI.parse(uri.to_s)
    return false if parsed.fragment || parsed.userinfo || parsed.host.blank?

    if LOOPBACK_HOSTS.include?(parsed.host)
      parsed.scheme.in?(%w[http https])
    else
      parsed.scheme == "https" && parsed.port == 443 &&
        REDIRECT_HOSTS.any? { |host| parsed.host == host || parsed.host.end_with?(".#{host}") }
    end
  rescue URI::InvalidURIError
    false
  end

  # RFC 7636: BASE64URL(SHA256(verifier)) without padding
  def self.pkce_matches?(verifier, challenge)
    return false unless verifier.is_a?(String) && verifier.match?(/\A[A-Za-z0-9\-._~]{43,128}\z/)

    expected = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, challenge.to_s)
  end
end

# frozen_string_literal: true

module Oauth
  # RFC 8414: where a client registers, sends someone to say yes, and gets tokens
  class AuthorizationServersController < ActionController::API
    def show
      issuer = request.base_url

      render json: {
        issuer:,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        revocation_endpoint: "#{issuer}/oauth/revoke",
        registration_endpoint: "#{issuer}/oauth/register",
        response_types_supported: [ "code" ],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: [ "none" ],
        revocation_endpoint_auth_methods_supported: [ "none" ],
        authorization_response_iss_parameter_supported: true
      }
    end
  end
end

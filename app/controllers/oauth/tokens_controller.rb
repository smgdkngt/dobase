# frozen_string_literal: true

module Oauth
  # The token endpoint: a consent code (with its PKCE verifier), a refresh
  # token or a confirmed device code (RFC 8628) for a fresh pair of tokens
  class TokensController < ActionController::API
    DEVICE_CODE = "urn:ietf:params:oauth:grant-type:device_code"

    rate_limit to: 60, within: 1.minute, with: -> { oauth_error("slow_down", :too_many_requests) }

    def create
      response.headers["Cache-Control"] = "no-store"
      client = Client.find_by(uid: params[:client_id].to_s)
      return oauth_error("invalid_client", :unauthorized) if client.nil?

      connection_and_grant = case params[:grant_type]
      when "authorization_code" then exchange_code(client)
      when "refresh_token" then Grant.refresh(params[:refresh_token], client:)
      when DEVICE_CODE
        connection = DeviceCode.poll(params[:device_code], client:)
        return oauth_error(connection) if connection.is_a?(String)

        Grant.issue(connection)
      else return oauth_error("unsupported_grant_type")
      end
      return oauth_error("invalid_grant") if connection_and_grant.nil?

      client.touch_last_used
      render_tokens(*connection_and_grant)
    end

    private

    def exchange_code(client)
      connection = AuthorizationCode.exchange(params[:code], client:, redirect_uri: params[:redirect_uri],
        code_verifier: params[:code_verifier])
      Grant.issue(connection) if connection
    end

    def render_tokens(grant, access, refresh)
      render json: {
        access_token: access,
        token_type: "Bearer",
        expires_in: (grant.expires_at - Time.current).round,
        refresh_token: refresh
      }
    end

    def oauth_error(error, status = :bad_request)
      render json: { error: }, status:
    end
  end
end

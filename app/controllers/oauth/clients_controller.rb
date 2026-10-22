# frozen_string_literal: true

module Oauth
  # RFC 7591 dynamic client registration, which is how Claude introduces itself.
  # Open to anyone, as the protocol expects: a client may only send people back
  # to Claude or to this computer, so a registration alone reaches nobody.
  class ClientsController < ActionController::API
    rate_limit to: 30, within: 1.hour, with: -> { render json: { error: "too_many_requests" }, status: :too_many_requests }

    def create
      client = Client.register(name: params[:client_name], redirect_uris: params[:redirect_uris])

      if client.persisted?
        render status: :created, json: {
          client_id: client.uid,
          client_id_issued_at: client.created_at.to_i,
          client_name: client.name,
          redirect_uris: client.redirect_uris,
          grant_types: %w[authorization_code refresh_token],
          response_types: [ "code" ],
          token_endpoint_auth_method: "none"
        }
      else
        render status: :bad_request,
          json: { error: "invalid_redirect_uri", error_description: client.errors.full_messages.to_sentence }
      end
    end
  end
end

# frozen_string_literal: true

module Oauth
  # RFC 8628: a client without a browser (the dobase CLI over SSH) asks for a
  # code to show, and where the person confirms it
  class DeviceAuthorizationsController < ActionController::API
    rate_limit to: 30, within: 1.hour, with: -> { render json: { error: "slow_down" }, status: :too_many_requests }

    def create
      client = Client.find_by(uid: params[:client_id].to_s)
      return render(json: { error: "invalid_client" }, status: :unauthorized) if client.nil?

      record, device_code = DeviceCode.issue(client)
      render json: {
        device_code:,
        user_code: record.user_code,
        verification_uri: new_oauth_device_url,
        verification_uri_complete: new_oauth_device_url(user_code: record.user_code),
        expires_in: DeviceCode::LIFETIME.to_i,
        interval: DeviceCode::INTERVAL
      }
    end
  end
end

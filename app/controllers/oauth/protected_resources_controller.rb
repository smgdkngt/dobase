# frozen_string_literal: true

module Oauth
  # RFC 9728: which server hands out tokens for `/mcp`
  class ProtectedResourcesController < ActionController::API
    def show
      render json: {
        resource: "#{request.base_url}/mcp",
        authorization_servers: [ request.base_url ],
        bearer_methods_supported: [ "header" ],
        resource_name: Rails.application.config.x.app.name
      }
    end
  end
end

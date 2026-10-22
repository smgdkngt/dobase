# frozen_string_literal: true

module Oauth
  # RFC 7009: a client ends its connection. The answer is the same whether the
  # token was known or not.
  class RevocationsController < ActionController::API
    def create
      client = Client.find_by(uid: params[:client_id].to_s)
      Grant.revoke(params[:token], client:) if client
      head :ok
    end
  end
end

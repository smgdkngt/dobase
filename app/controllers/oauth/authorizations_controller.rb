# frozen_string_literal: true

module Oauth
  # The page a client sends someone to: signed in as themselves (the normal
  # sign-in brings them back here), they say yes or no, whether the client may
  # change things or only read, and whether what it writes shows under its own
  # name ("Claude for Sem") or under theirs ("via Claude").
  class AuthorizationsController < ApplicationController
    before_action :load_authorization_request
    restrict_in_demo

    def new
      return render(:invalid, status: :bad_request) unless @authorization.redirect_trusted?
      return redirect_back_to_client(error: @authorization.error) unless @authorization.valid?

      render :disabled, status: :forbidden unless current_user.mcp_enabled?
    end

    def create
      return render(:invalid, status: :bad_request) unless @authorization.redirect_trusted?
      return redirect_back_to_client(error: @authorization.error) unless @authorization.valid?
      return render(:disabled, status: :forbidden) unless current_user.mcp_enabled?
      return redirect_back_to_client(error: "access_denied") unless params[:decision] == "allow"

      _, code = AuthorizationCode.issue(client: @authorization.client, user: current_user,
        redirect_uri: @authorization.redirect_uri, code_challenge: @authorization.code_challenge,
        permission: params[:permission] == "read" ? "read" : "write", agent: params[:agent] != "false")
      redirect_back_to_client(code:)
    end

    private

    def load_authorization_request
      @authorization = AuthorizationRequest.new(params)
    end

    def redirect_back_to_client(**result)
      redirect_to @authorization.redirect_with(issuer: request.base_url, **result), allow_other_host: true
    end
  end
end

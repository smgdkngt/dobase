# frozen_string_literal: true

module Profiles
  class AccessTokensController < ApplicationController
    def create
      access_token = current_user.access_tokens.new(params.permit(:name, :permission))

      if access_token.save
        render_access_tokens created_token: access_token.token
      else
        render_access_tokens access_token: access_token, status: :unprocessable_entity
      end
    end

    def destroy
      current_user.access_tokens.find(params[:id]).destroy
      redirect_to edit_profile_path(tab: "api"), status: :see_other
    end

    private

    def render_access_tokens(access_token: AccessToken.new, created_token: nil, status: :ok)
      render partial: "profiles/access_tokens", status: status, locals: {
        access_tokens: current_user.access_tokens.newest_first,
        access_token: access_token,
        created_token: created_token
      }
    end
  end
end

# frozen_string_literal: true

module Tools
  module Files
    module Shares
      # Unlocks a password-protected share link for this browser session. The password
      # is posted, so it doesn't end up in URLs, browser history or access logs.
      class UnlocksController < ApplicationController
        include ShareAuthentication

        skip_before_action :require_unlocked_share
        rate_limit to: 10, within: 3.minutes, only: :create,
          with: -> { refuse_unlock("Too many attempts. Try again in a few minutes.", :too_many_requests) }

        def create
          if @share_not_found || @share_expired || !@share.password_protected?
            redirect_to share_path(params[:share_token]), status: :see_other
          elsif @share.authenticate(params[:password].to_s)
            unlock_share
            redirect_to share_path(@share.token), status: :see_other
          else
            refuse_unlock("Incorrect password", :unprocessable_entity)
          end
        end

        private

        def refuse_unlock(message, status)
          @password_required = true
          @password_error = message
          render "tools/files/shares/show", status: status
        end
      end
    end
  end
end

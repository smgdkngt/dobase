# frozen_string_literal: true

module ShareAuthentication
  extend ActiveSupport::Concern

  included do
    skip_before_action :require_authentication

    layout "public"

    before_action :set_share
    before_action :check_expiration
    before_action :check_password, if: -> { @share&.password_protected? }
  end

  private

  def set_share
    @share = ::Files::Share.find_by!(token: params[:share_token] || params[:token])
  rescue ActiveRecord::RecordNotFound
    @share_not_found = true
  end

  def check_expiration
    @share_expired = @share&.expired?
  end

  SHARE_SESSION_TTL = 30.minutes

  def check_password
    session_key = "share_#{@share.id}_authenticated_at"
    authenticated_at = session[session_key]

    if authenticated_at.present? && Time.zone.parse(authenticated_at) > SHARE_SESSION_TTL.ago
      return
    end

    session.delete(session_key)

    if params[:password].present? && @share.authenticate(params[:password])
      session[session_key] = Time.current.iso8601
    else
      @password_error = "Incorrect password" if params[:password].present?
      @password_required = true
    end
  end
end

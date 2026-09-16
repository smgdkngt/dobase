# frozen_string_literal: true

module ShareAuthentication
  extend ActiveSupport::Concern

  included do
    skip_before_action :require_authentication

    layout "public"

    before_action :set_share
    before_action :check_expiration
    before_action :check_password, if: -> { @share&.password_protected? }
    before_action :require_unlocked_share
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

  # A password-protected link stays unlocked for this browser session for a while.
  # The password itself is posted to UnlocksController, never sent in a URL.
  def check_password
    authenticated_at = session[share_session_key]
    return if authenticated_at.present? && Time.zone.parse(authenticated_at) > SHARE_SESSION_TTL.ago

    session.delete(share_session_key)
    @password_required = true
  end

  def unlock_share
    session[share_session_key] = Time.current.iso8601
  end

  def share_session_key
    "share_#{@share.id}_authenticated_at"
  end

  # Nothing behind a link is served until the share exists, hasn't expired and,
  # if it has a password, has been unlocked. The share page says which one it is.
  def require_unlocked_share
    if @share_not_found
      render "tools/files/shares/show", status: :not_found
    elsif @share_expired
      render "tools/files/shares/show", status: :gone
    elsif @password_required
      render "tools/files/shares/show", status: :unauthorized
    end
  end
end

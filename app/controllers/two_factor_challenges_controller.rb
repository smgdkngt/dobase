# frozen_string_literal: true

class TwoFactorChallengesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_two_factor_challenge_path, alert: "Too many attempts. Try again later." }

  before_action :ensure_otp_user

  def new
  end

  def create
    code = params[:code].to_s.strip

    if @user.verify_otp(code) || @user.verify_recovery_code(code)
      session.delete(:otp_user_id)
      start_new_session_for @user
      redirect_to after_authentication_url
    else
      flash.now[:alert] = "Invalid code. Please try again."
      render :new, status: :unprocessable_entity
    end
  end

  private

  def ensure_otp_user
    @user = User.find_by(id: session[:otp_user_id])

    unless @user&.otp_required?
      session.delete(:otp_user_id)
      redirect_to new_session_path
    end
  end
end

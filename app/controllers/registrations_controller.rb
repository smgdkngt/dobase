# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many attempts. Try again later." }

  def new
    redirect_to root_path if authenticated?
    @user = User.new
  end

  def create
    unless verify_altcha
      @user = User.new(user_params)
      flash.now[:alert] = "Please complete the verification."
      return render :new, status: :unprocessable_entity
    end

    @user = User.new(user_params)

    if @user.save
      start_new_session_for(@user)

      if (redirect_path = accept_pending_invitation(@user))
        redirect_to redirect_path, notice: "Welcome to #{helpers.app_name}! You've been added as a collaborator."
      else
        redirect_to root_path, notice: "Welcome to #{helpers.app_name}, #{@user.first_name}!"
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def verify_altcha
    payload = params[:altcha]
    return false if payload.blank?

    parsed = JSON.parse(Base64.decode64(payload), symbolize_names: true)
    Altcha.verify_solution(parsed, altcha_hmac_key)
  rescue JSON::ParserError, ArgumentError
    false
  end

  def altcha_hmac_key
    Rails.application.secret_key_base.first(32)
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email_address, :password, :password_confirmation)
  end

  def accept_pending_invitation(user)
    token = session.delete(:pending_invitation_token)
    return unless token

    invitation = Invitation.find_by(token: token)
    return unless invitation&.acceptable?

    invitation.accept!(user)
    tool_path(invitation.tool)
  end
end

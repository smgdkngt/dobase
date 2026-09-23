# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to signup_path, alert: "Too many attempts. Try again later." }

  def new
    return redirect_to root_path if authenticated?

    unless registration_allowed?
      redirect_to login_path, alert: "Registration is by invitation only."
      return
    end
    @user = User.new(email_address: pending_invitation&.email)
    @first_user = User.none?
  end

  def create
    unless registration_allowed?
      redirect_to login_path, alert: "Registration is by invitation only."
      return
    end

    unless User.none? || verify_altcha
      @user = User.new(user_params)
      flash.now[:alert] = "Please complete the verification."
      return render :new, status: :unprocessable_entity
    end

    @user = User.new(user_params)
    # An invitation is for its address, so signing up through one uses that address
    @user.email_address = pending_invitation.email if pending_invitation

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

  def registration_allowed?
    # Visitors of the demo try it without an account
    return false if Demo.enabled?
    # Open registration when no users exist (first user setup)
    return true if User.none?
    # Allow registration via a valid invitation link
    return true if pending_invitation
    # Otherwise closed unless explicitly enabled
    ENV["OPEN_REGISTRATION"] == "true"
  end

  def verify_altcha
    payload = params[:altcha]
    return false if payload.blank?

    parsed = JSON.parse(Base64.decode64(payload), symbolize_names: true)
    Altcha::V1.verify_solution(parsed, altcha_hmac_key)
  rescue JSON::ParserError, ArgumentError
    false
  end

  def altcha_hmac_key
    Rails.application.secret_key_base.first(32)
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email_address, :password, :password_confirmation)
  end

  def pending_invitation
    return @pending_invitation if defined?(@pending_invitation)

    invitation = Invitation.find_by(token: session[:pending_invitation_token]) if session[:pending_invitation_token].present?
    @pending_invitation = invitation if invitation&.acceptable?
  end
  helper_method :pending_invitation

  def accept_pending_invitation(user)
    invitation = pending_invitation
    session.delete(:pending_invitation_token)
    return unless invitation&.for?(user)

    invitation.accept!(user)
    tool_path(invitation.tool)
  end
end

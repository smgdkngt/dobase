# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many attempts. Try again later." }

  def new
    redirect_to root_path if authenticated?
    @user = User.new
  end

  def create
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

class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if user.otp_required?
        session[:otp_user_id] = user.id
        redirect_to new_two_factor_challenge_path
      else
        start_new_session_for user
        redirect_to after_authentication_url
      end
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    if params[:id]
      # Revoke a specific other session
      session_to_revoke = current_user.sessions.find(params[:id])
      session_to_revoke.destroy
      redirect_to edit_profile_path(tab: "sessions"), notice: "Session revoked."
    else
      # Log out current session
      terminate_session
      redirect_to new_session_path, status: :see_other
    end
  end
end

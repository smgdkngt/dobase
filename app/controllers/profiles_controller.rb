# frozen_string_literal: true

class ProfilesController < ApplicationController
  def edit
    @user = current_user
    @sessions = current_user.sessions.order(created_at: :desc)
  end

  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to root_path, notice: "Profile updated."
    else
      @sessions = current_user.sessions.order(created_at: :desc)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    user = current_user
    terminate_session
    user.destroy!
    redirect_to new_session_path, notice: "Your account has been deleted."
  end

  private

  def profile_params
    permitted = params.require(:user).permit(:first_name, :last_name, :email_address, :avatar, :timezone, :password, :password_confirmation)
    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end
    permitted
  end
end

# frozen_string_literal: true

class ProfilesController < ApplicationController
  allow_access_tokens only: :show

  def show
    respond_to do |format|
      format.html { redirect_to edit_profile_path }
      format.json { @user = current_user }
    end
  end

  def edit
    @user = current_user
    @sessions = current_user.sessions.order(created_at: :desc)
    @access_tokens = current_user.access_tokens.newest_first
  end

  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to root_path, notice: "Profile updated."
    else
      @sessions = current_user.sessions.order(created_at: :desc)
      @access_tokens = current_user.access_tokens.newest_first
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
    permitted = params.require(:user).permit(:first_name, :last_name, :email_address, :avatar, :timezone, :notification_digest, :password, :password_confirmation)
    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end
    permitted
  end
end

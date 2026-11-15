# frozen_string_literal: true

class ProfilesController < ApplicationController
  allow_access_tokens only: :show
  restrict_in_demo only: :update, if: -> { params.dig(:user, :avatar).present? }

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
    new_password = profile_params[:password].present?

    if new_password && !@user.authenticate(params[:user][:current_password].to_s)
      return refuse_update("Your current password is incorrect.")
    end

    if @user.update(profile_params)
      # A new password ends the other sessions, so someone who got into one can't stay
      @user.sessions.where.not(id: Current.session.id).destroy_all if new_password
      redirect_to root_path, notice: new_password ? "Password updated. Other sessions have been signed out." : "Profile updated."
    else
      refuse_update
    end
  end

  def destroy
    user = current_user
    terminate_session
    user.destroy!
    redirect_to new_session_path, notice: "Your account has been deleted."
  end

  private

  TABS = %w[profile notifications security].freeze

  # The form that was sent comes back on the tab it was sent from, saying why. From
  # the profile dialog it comes back into the dialog (a stream), so the page the
  # dialog is over (the workspace) stays as it was.
  def refuse_update(alert = nil)
    flash.now[:alert] = alert if alert
    @sessions = current_user.sessions.order(created_at: :desc)
    @access_tokens = current_user.access_tokens.newest_first
    @open_tab = params[:tab].presence_in(TABS) || "profile"

    respond_to do |format|
      # Only from the dialog: the profile page has a frame of that name too, after the
      # sidebar's dialog, and a stream goes to the first one
      if params[:dialog].present?
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("profile-form", partial: "profiles/settings",
            locals: { user: @user, in_dialog: true, tab: @open_tab, open_tab: @open_tab }),
            status: :unprocessable_entity
        end
      end
      format.html { render :edit, status: :unprocessable_entity }
    end
  end

  def profile_params
    permitted = params.require(:user).permit(:first_name, :last_name, :email_address, :avatar, :timezone, :notification_digest, :password, :password_confirmation)
    # Demo visitors are known by their address, which is how they are cleaned up
    permitted.delete(:email_address) if Demo.enabled?
    if permitted[:password].blank?
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end
    permitted
  end
end

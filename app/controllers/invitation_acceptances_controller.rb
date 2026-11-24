# frozen_string_literal: true

class InvitationAcceptancesController < ApplicationController
  allow_unauthenticated_access only: [ :show, :create, :destroy ]

  before_action :set_invitation

  def show
    if authenticated?
      @tool = @invitation.tool
      @inviter = @invitation.invited_by
    else
      redirect_to_authentication
    end
  end

  def create
    if !authenticated?
      redirect_to_authentication
    elsif @invitation.for?(current_user)
      @invitation.accept!(current_user)
      redirect_to tool_path(@invitation.tool),
                  notice: _("You are now a collaborator on %{name}!", name: @invitation.tool.name)
    else
      redirect_to invitation_acceptance_path(token: @invitation.token),
                  alert: _("This invitation is for %{email}. Sign in with that address to accept it.", email: @invitation.email)
    end
  end

  def destroy
    @invitation.decline!
    redirect_to root_path, notice: _("Invitation declined.")
  end

  private

  def set_invitation
    @invitation = Invitation.find_by!(token: params[:token])

    unless @invitation.acceptable?
      message = @invitation.expired? ? _("This invitation has expired.") : _("This invitation is no longer valid.")
      redirect_to root_path, alert: message
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: _("Invalid invitation link.")
  end

  def redirect_to_authentication
    existing_user = User.find_by(email_address: @invitation.email)

    if existing_user
      session[:return_to_after_authenticating] = invitation_acceptance_url(token: @invitation.token)
      redirect_to new_session_path, notice: _("Please sign in to accept the invitation.")
    else
      session[:pending_invitation_token] = @invitation.token
      redirect_to signup_path, notice: _("Create an account to accept the invitation.")
    end
  end
end

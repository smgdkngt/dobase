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
    if authenticated?
      @invitation.accept!(current_user)
      redirect_to tool_path(@invitation.tool),
                  notice: "You are now a collaborator on #{@invitation.tool.name}!"
    else
      redirect_to_authentication
    end
  end

  def destroy
    @invitation.decline!
    redirect_to root_path, notice: "Invitation declined."
  end

  private

  def set_invitation
    @invitation = Invitation.find_by!(token: params[:token])

    unless @invitation.acceptable?
      message = @invitation.expired? ? "This invitation has expired." : "This invitation is no longer valid."
      redirect_to root_path, alert: message
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Invalid invitation link."
  end

  def redirect_to_authentication
    existing_user = User.find_by(email_address: @invitation.email)

    if existing_user
      session[:return_to_after_authenticating] = invitation_acceptance_url(token: @invitation.token)
      redirect_to new_session_path, notice: "Please sign in to accept the invitation."
    else
      session[:pending_invitation_token] = @invitation.token
      redirect_to signup_path, notice: "Create an account to accept the invitation."
    end
  end
end

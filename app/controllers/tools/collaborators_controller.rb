# frozen_string_literal: true

module Tools
  class CollaboratorsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_owner!(@tool) }, except: [ :leave ]
    before_action -> { authorize_tool_access!(@tool) }, only: [ :leave ]

    def leave
      collaborator = @tool.collaborators.find_by(user: current_user)
      unless collaborator
        redirect_to root_path, alert: "You are not a collaborator on this tool." and return
      end

      if collaborator.role == "owner" && @tool.collaborators.owners.count == 1
        redirect_to edit_tool_path(@tool, tab: "collaborators"), alert: "You are the only owner. Promote another owner before leaving."
        return
      end

      collaborator.destroy
      current_user.update_column(:last_visited_path, nil)
      redirect_to root_path, notice: "You left #{@tool.name}."
    end

    def create
      email = params[:email]&.downcase&.strip

      if email == current_user.email_address
        redirect_to edit_tool_path(@tool, tab: "collaborators"), alert: "You cannot invite yourself."
        return
      end

      existing = @tool.invitations.active.find_by(email: email)
      if existing
        redirect_to edit_tool_path(@tool, tab: "collaborators"), alert: "Invitation already pending."
        return
      end

      # Clean up old declined/expired invitations for this email
      @tool.invitations.where(email: email).where.not(status: "pending").destroy_all

      invitation = @tool.invitations.build(email: email, invited_by: current_user)

      if invitation.save
        CollaboratorMailer.invitation(invitation).deliver_later
        notify_invitation(invitation, email)
        redirect_to edit_tool_path(@tool, tab: "collaborators"), notice: "Invitation sent to #{email}."
      else
        redirect_to edit_tool_path(@tool, tab: "collaborators"), alert: invitation.errors.full_messages.first
      end
    end

    def update
      collaborator = @tool.collaborators.find(params[:id])
      collaborator.update!(role: "owner")
      redirect_to edit_tool_path(@tool, tab: "collaborators"), notice: "#{collaborator.user.name} is now an owner."
    end

    def destroy
      collaborator = @tool.collaborators.find(params[:id])
      if collaborator.role == "owner"
        redirect_to edit_tool_path(@tool, tab: "collaborators"), alert: "Cannot remove an owner."
      else
        collaborator.destroy
        redirect_to edit_tool_path(@tool, tab: "collaborators")
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

    def notify_invitation(invitation, email)
      invited_user = User.find_by(email_address: email)
      return unless invited_user

      ToolInvitationNotifier.with(
        invitation: invitation,
        tool: @tool,
        invited_by: current_user,
        recipient_user: invited_user
      ).deliver(invited_user)
      invited_user.prune_notifications!
    end
  end
end

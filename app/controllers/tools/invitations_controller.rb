# frozen_string_literal: true

module Tools
  class InvitationsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_owner!(@tool) }
    # Invitations go out by email
    restrict_in_demo only: :resend

    def resend
      invitation = @tool.invitations.find(params[:id])

      if invitation.update(status: "pending", expires_at: 7.days.from_now)
        CollaboratorMailer.invitation(invitation).deliver_later
        redirect_to edit_tool_path(@tool, tab: "collaborators"), notice: "Invitation resent."
      else
        redirect_to edit_tool_path(@tool, tab: "collaborators"), alert: invitation.errors.full_messages.first
      end
    end

    def cancel
      invitation = @tool.invitations.pending.find(params[:id])
      invitation.update!(status: "declined")
      redirect_to edit_tool_path(@tool)
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end
  end
end

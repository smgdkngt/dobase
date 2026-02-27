# frozen_string_literal: true

module Tools
  class InvitationsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_owner!(@tool) }

    def resend
      invitation = @tool.invitations.find(params[:id])
      invitation.update!(status: "pending", expires_at: 7.days.from_now)
      CollaboratorMailer.invitation(invitation).deliver_later
      redirect_to edit_tool_path(@tool, tab: "collaborators"), notice: "Invitation resent."
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

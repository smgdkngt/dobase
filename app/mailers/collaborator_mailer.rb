# frozen_string_literal: true

class CollaboratorMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @tool = invitation.tool
    @inviter = invitation.invited_by
    @accept_url = invitation_acceptance_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: "#{@inviter.name} invited you to collaborate on #{@tool.name}"
    )
  end
end

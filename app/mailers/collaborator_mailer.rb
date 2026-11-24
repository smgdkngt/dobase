# frozen_string_literal: true

class CollaboratorMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @tool = invitation.tool
    @inviter = invitation.invited_by
    @accept_url = invitation_acceptance_url(token: invitation.token)

    in_language_of(User.find_by(email_address: invitation.email), fallback: @inviter) do
      mail(
        to: invitation.email,
        subject: _("%{person} invited you to collaborate on %{tool}", person: @inviter.name, tool: @tool.name)
      )
    end
  end
end

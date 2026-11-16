# frozen_string_literal: true

module Tools
  module Calendars
    # The Undo on "Added to <calendar>": the invitation is open again, and the event it
    # made is gone from the calendar (Calendars::InviteAcceptance)
    class InviteAcceptancesController < ApplicationController
      include ToolScoped

      # DELETE /tools/:tool_id/calendar/invite_acceptances/:id
      def destroy
        invite = ::Calendars::Invite.joins(mail_message: :account)
          .where(mail_accounts: { tool_id: current_user.accessible_tools.select(:id) })
          .find(params[:id])
        message = invite.mail_message
        acceptance = ::Calendars::InviteAcceptance.find(params[:token], invite: invite, user: current_user)

        if acceptance
          removed = acceptance.undo
          redirect_to tool_mail_path(message.account.tool, message),
            notice: removed ? "Taken out of the calendar again." : "The invitation is open again."
        else
          redirect_to tool_mail_path(message.account.tool, message), alert: "That can't be undone any more."
        end
      end
    end
  end
end

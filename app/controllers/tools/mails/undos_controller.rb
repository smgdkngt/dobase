# frozen_string_literal: true

module Tools
  module Mails
    # The Undo button on "Email archived." and the like (Mails::Undo): what it names goes
    # back where it was, through the account's own methods. Only for whoever it was made
    # for, in the mail tool it was made in, for a few minutes.
    class UndosController < ApplicationController
      include ToolScoped

      # POST /tools/:tool_id/undo
      def create
        account = @tool.mail_account
        undo = ::Mails::Undo.find(params[:undo], account: account, user: Current.user) if account

        unless undo
          redirect_back_or_to tool_mails_path(@tool), alert: _("That can't be undone any more.")
          return
        end

        undo.apply
        undone = account.messages.where(id: undo.places.map(&:first))
        message = undone.order(sent_at: :desc).first
        unless message
          redirect_back_or_to tool_mails_path(@tool), alert: _("That mail is gone.")
          return
        end

        # One conversation opens where it is again, more than one show in their folder's list
        folder = account.view_of(message)
        if undone.distinct.count(:thread_id) <= 1
          redirect_to tool_mail_path(@tool, message, folder: folder), notice: _("Undone.")
        else
          redirect_to tool_mails_path(@tool, folder: folder), notice: _("Undone.")
        end
      end
    end
  end
end

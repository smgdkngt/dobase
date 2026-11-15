# frozen_string_literal: true

module Tools
  module Mails
    class AccountsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_owner!(@tool) }
      before_action :set_mail_account, only: [ :update ]
      restrict_in_demo only: %i[create update]

      def new
        @mail_account = @tool.build_mail_account
      end

      # The login is tried before anything is saved: a password the server turns down
      # is said here, not as an empty inbox later
      def create
        @mail_account = @tool.build_mail_account(mail_account_params)

        if connects? && @mail_account.save
          SyncEmailsJob.perform_later(@mail_account.id)
          redirect_to tool_mails_path(@tool), notice: "Mail account connected successfully."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def update
        @mail_account.assign_attributes(mail_account_params)
        if connects? && @mail_account.save
          if @mail_account.saved_changes.keys.intersect?(::Mails::Account::CONNECTION_SETTINGS)
            @mail_account.mark_syncing!
            SyncEmailsJob.perform_later(@mail_account.id)
          end
          redirect_to tool_mails_path(@tool), notice: "Mail account updated successfully."
        else
          # The mail account is edited in the tool's settings
          render "tools/edit", status: :unprocessable_entity
        end
      end

      private

      # Valid, and a login both servers take when the settings for it are new or changed
      def connects?
        return false unless @mail_account.valid?
        return true if @mail_account.persisted? && !@mail_account.changed.intersect?(::Mails::ConnectionCheck::SETTINGS)

        problem = ::Mails::ConnectionCheck.new(@mail_account).problem
        @mail_account.errors.add(:base, problem) if problem
        problem.nil?
      end

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_mail_account
        @mail_account = @tool.mail_account
        redirect_to @tool, alert: "No mail account configured." unless @mail_account
      end

      def mail_account_params
        params.require(:mails_account).permit(
          :email_address, :display_name,
          :imap_host, :imap_port, :imap_ssl,
          :smtp_host, :smtp_port, :smtp_auth, :smtp_tls,
          :username, :password,
          :signature, :auto_refresh_interval, :archive_folder
        )
      end
    end
  end
end

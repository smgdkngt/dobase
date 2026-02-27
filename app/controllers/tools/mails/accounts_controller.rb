# frozen_string_literal: true

module Tools
  module Mails
    class AccountsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_owner!(@tool) }
      before_action :set_mail_account, only: [ :update ]

      def new
        @mail_account = @tool.build_mail_account
      end

      def create
        @mail_account = @tool.build_mail_account(mail_account_params)

        if @mail_account.save
          SyncEmailsJob.perform_later(@mail_account.id)
          redirect_to tool_mails_path(@tool), notice: "Mail account connected successfully."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def update
        if @mail_account.update(mail_account_params)
          redirect_to tool_mails_path(@tool), notice: "Mail account updated successfully."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def test_connection
        @mail_account = @tool.mail_account || @tool.build_mail_account(mail_account_params)

        begin
          imap_service = ImapSyncService.new(@mail_account)
          imap_service.test_connection

          smtp_service = SmtpSendService.new(@mail_account)
          smtp_service.test_connection

          render json: { success: true, message: "Connection successful!" }
        rescue ImapSyncService::ConnectionError, ImapSyncService::AuthenticationError => e
          render json: { success: false, message: "IMAP: #{e.message}" }, status: :unprocessable_entity
        rescue SmtpSendService::ConnectionError => e
          render json: { success: false, message: "SMTP: #{e.message}" }, status: :unprocessable_entity
        end
      end

      private

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
          :signature, :auto_refresh_interval
        )
      end
    end
  end
end

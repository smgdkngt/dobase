# frozen_string_literal: true

module Tools
  module Calendars
    class AccountsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_owner!(@tool) }
      before_action :set_calendar_account, only: %i[edit update]

      def new
        @calendar_account = @tool.build_calendar_account
      end

      def create
        if params.dig(:calendars_account, :provider) == "local"
          create_local_calendar
        else
          create_caldav_account
        end
      end

      def edit
      end

      def update
        if @calendar_account.update(calendar_account_params)
          redirect_to tool_calendar_path(@tool), notice: "Calendar account updated successfully."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def test_connection
        @calendar_account = @tool.calendar_account || @tool.build_calendar_account(calendar_account_params)

        begin
          service = CaldavSyncService.new(@calendar_account)
          service.test_connection

          render json: { success: true, message: "Connection successful!" }
        rescue CaldavSyncService::AuthenticationError => e
          render json: { success: false, message: "Authentication failed: #{e.message}" }, status: :unprocessable_entity
        rescue CaldavSyncService::ConnectionError => e
          render json: { success: false, message: "Connection failed: #{e.message}" }, status: :unprocessable_entity
        end
      end

      private

      def set_tool
        @tool = Tool.find_by(id: params[:tool_id])
        redirect_to root_path, alert: "Tool not found." unless @tool
      end

      def set_calendar_account
        @calendar_account = @tool.calendar_account
        redirect_to @tool, alert: "No calendar account configured." unless @calendar_account
      end

      def calendar_account_params
        params.require(:calendars_account).permit(
          :provider,
          :caldav_url,
          :username,
          :password,
          calendars_attributes: [ :id, :name, :color, :enabled ]
        )
      end

      def create_local_calendar
        @tool.calendars.create!(
          name: @tool.name,
          color: "#3b82f6",
          enabled: true,
          is_default: true,
          position: 0,
          remote_id: nil
        )
        redirect_to tool_calendar_path(@tool), notice: "Calendar created successfully."
      end

      def create_caldav_account
        @calendar_account = @tool.build_calendar_account(calendar_account_params)

        if @calendar_account.save
          SyncCalendarsJob.perform_later(@calendar_account.id)
          redirect_to tool_calendar_path(@tool), notice: "Calendar account connected successfully."
        else
          render :new, status: :unprocessable_entity
        end
      end
    end
  end
end

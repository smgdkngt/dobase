# frozen_string_literal: true

module Oauth
  # Where someone types the code `dobase login` shows, signed in as themselves,
  # and says yes or no, as on the consent page for Claude
  class DevicesController < ApplicationController
    restrict_in_demo
    rate_limit to: 10, within: 1.minute, only: :create, by: -> { current_user.id },
      with: -> { redirect_to new_oauth_device_path, alert: "Too many tries. Wait a minute." }

    def new
      return render("oauth/authorizations/disabled", status: :forbidden) unless current_user.mcp_enabled?

      @user_code = params[:user_code].to_s
      @device = DeviceCode.waiting(@user_code) if @user_code.present?
    end

    def create
      return render("oauth/authorizations/disabled", status: :forbidden) unless current_user.mcp_enabled?

      device = DeviceCode.waiting(params[:user_code])
      if device.nil?
        redirect_to new_oauth_device_path, alert: "That code isn't valid, or has expired. Run dobase login again."
      elsif params[:decision] == "allow"
        device.approve(current_user, permission: params[:permission] == "read" ? "read" : "write", agent: params[:agent] == "true")
        render :connected
      else
        device.deny
        redirect_to new_oauth_device_path, notice: "Not connected."
      end
    end
  end
end

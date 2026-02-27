# frozen_string_literal: true

class TwoFactorSetupsController < ApplicationController
  def new
    secret = ROTP::Base32.random
    session[:pending_otp_secret] = secret

    @otp_secret = secret
    @qr_svg = generate_qr_svg(secret)
  end

  def create
    secret = session[:pending_otp_secret]
    unless secret
      redirect_to edit_profile_path(tab: "security"), alert: "Setup expired. Please try again."
      return
    end

    totp = ROTP::TOTP.new(secret, issuer: Rails.application.config.x.app.name)
    if totp.verify(params[:code].to_s.strip, drift_behind: 15, drift_ahead: 15)
      current_user.update!(otp_secret: secret, otp_required: true)
      @recovery_codes = current_user.generate_recovery_codes
      session.delete(:pending_otp_secret)
    else
      @otp_secret = secret
      @qr_svg = generate_qr_svg(secret)
      flash.now[:alert] = "Invalid code. Please try again."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user.authenticate(params[:password].to_s)
      redirect_to edit_profile_path(tab: "security"), alert: "Incorrect password."
      return
    end

    current_user.update!(otp_secret: nil, otp_required: false, otp_recovery_codes: nil)
    redirect_to edit_profile_path(tab: "security")
  end

  private

  def generate_qr_svg(secret)
    totp = ROTP::TOTP.new(secret, issuer: Rails.application.config.x.app.name)
    uri = totp.provisioning_uri(current_user.email_address)
    qr = RQRCode::QRCode.new(uri)
    qr.as_svg(
      module_size: 4,
      standalone: true,
      use_path: true,
      viewbox: true,
      svg_attributes: { class: "w-48 h-48 mx-auto" }
    )
  end
end

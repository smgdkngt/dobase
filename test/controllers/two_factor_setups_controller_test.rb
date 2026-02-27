# frozen_string_literal: true

require "test_helper"

class TwoFactorSetupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "new renders QR code and secret" do
    get new_two_factor_setup_path
    assert_response :success
    assert_select "svg"
    assert_select "details"
  end

  test "create with valid code enables 2FA and shows recovery codes" do
    get new_two_factor_setup_path

    secret = session[:pending_otp_secret]
    totp = ROTP::TOTP.new(secret)
    valid_code = totp.now

    post two_factor_setup_path, params: { code: valid_code }
    assert_response :success

    @user.reload
    assert @user.otp_required?
    assert @user.otp_secret.present?
    assert @user.otp_recovery_codes.present?
  end

  test "create with invalid code re-renders setup" do
    get new_two_factor_setup_path

    post two_factor_setup_path, params: { code: "000000" }
    assert_response :unprocessable_entity
  end

  test "destroy with correct password disables 2FA" do
    @user.update!(otp_secret: ROTP::Base32.random, otp_required: true)

    delete two_factor_setup_path, params: { password: "password" }
    assert_redirected_to edit_profile_path(tab: "security")

    @user.reload
    assert_not @user.otp_required?
    assert_nil @user.otp_secret
  end

  test "destroy with wrong password does not disable 2FA" do
    @user.update!(otp_secret: ROTP::Base32.random, otp_required: true)

    delete two_factor_setup_path, params: { password: "wrong" }
    assert_redirected_to edit_profile_path(tab: "security")

    @user.reload
    assert @user.otp_required?
  end
end

# frozen_string_literal: true

require "test_helper"

class TwoFactorChallengesControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:with_otp) }

  test "new redirects to login without otp_user_id in session" do
    get new_two_factor_challenge_path
    assert_redirected_to new_session_path
  end

  test "new renders verification form with otp_user_id in session" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to new_two_factor_challenge_path

    get new_two_factor_challenge_path
    assert_response :success
    assert_select "input[name=code]"
  end

  test "create with valid TOTP code signs in" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    follow_redirect!

    valid_code = @user.otp.now
    post two_factor_challenge_path, params: { code: valid_code }

    assert_redirected_to root_path
    assert cookies[:session_id].present?
  end

  test "create with invalid code re-renders form" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    follow_redirect!

    post two_factor_challenge_path, params: { code: "000000" }
    assert_response :unprocessable_entity
  end

  test "create with valid recovery code signs in and consumes it" do
    codes = @user.generate_recovery_codes

    post session_path, params: { email_address: @user.email_address, password: "password" }
    follow_redirect!

    post two_factor_challenge_path, params: { code: codes.first }

    assert_redirected_to root_path
    assert cookies[:session_id].present?

    # Code should be consumed
    @user.reload
    remaining = JSON.parse(@user.otp_recovery_codes)
    assert_equal codes.length - 1, remaining.length
  end

  test "login redirects to 2FA verify for user with otp_required" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to new_two_factor_challenge_path
    assert_nil cookies[:session_id].presence
  end
end

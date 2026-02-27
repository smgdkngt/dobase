# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "edit renders profile form with sessions" do
    get edit_profile_path
    assert_response :success
  end

  test "update profile details without password" do
    patch profile_path, params: { user: { first_name: "Updated", last_name: "Name", email_address: @user.email_address, password: "", password_confirmation: "" } }
    assert_redirected_to root_path

    @user.reload
    assert_equal "Updated", @user.first_name
  end

  test "update with blank password does not change password digest" do
    original_digest = @user.password_digest

    patch profile_path, params: { user: { first_name: @user.first_name, last_name: @user.last_name, email_address: @user.email_address, password: "", password_confirmation: "" } }
    assert_redirected_to root_path

    @user.reload
    assert_equal original_digest, @user.password_digest
  end

  test "update password with valid confirmation" do
    patch profile_path, params: { user: { first_name: @user.first_name, last_name: @user.last_name, email_address: @user.email_address, password: "newpassword123", password_confirmation: "newpassword123" } }
    assert_redirected_to root_path

    @user.reload
    assert @user.authenticate("newpassword123")
  end

  test "destroy deletes account and redirects to login" do
    assert_difference "User.count", -1 do
      delete profile_path
    end
    assert_redirected_to new_session_path
  end
end

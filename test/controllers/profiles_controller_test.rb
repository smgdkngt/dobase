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
    patch profile_path, params: { user: { first_name: @user.first_name, last_name: @user.last_name, email_address: @user.email_address, password: "newpassword123", password_confirmation: "newpassword123", current_password: "password" } }
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

  test "changing the password needs the current one" do
    old_digest = @user.password_digest

    patch profile_path, params: { user: { password: "brand-new-secret", password_confirmation: "brand-new-secret", current_password: "wrong" } }

    assert_response :unprocessable_entity
    assert_equal old_digest, @user.reload.password_digest
  end

  test "a new password signs the other sessions out" do
    other = @user.sessions.create!(user_agent: "Another browser", ip_address: "10.0.0.9")

    patch profile_path, params: { user: { password: "brand-new-secret", password_confirmation: "brand-new-secret", current_password: "password" } }

    assert_redirected_to root_path
    assert @user.reload.authenticate("brand-new-secret")
    assert_not Session.exists?(other.id)
    assert Session.exists?(Current.session&.id || @user.sessions.first.id)
  end

  test "the rest of the profile saves without a password" do
    patch profile_path, params: { user: { first_name: "Renamed" } }

    assert_redirected_to root_path
    assert_equal "Renamed", @user.reload.first_name
  end
end

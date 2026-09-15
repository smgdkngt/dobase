# frozen_string_literal: true

require "test_helper"

module Profiles
  class AccessTokensControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as @user
    end

    test "profile edit lists access tokens" do
      @user.access_tokens.create!(name: "Laptop CLI", permission: "write")

      get edit_profile_path(tab: "api")

      assert_response :success
      assert_includes response.body, "Laptop CLI"
      assert_includes response.body, "Read and write"
    end

    test "create reveals the new token once" do
      assert_difference -> { @user.access_tokens.count }, 1 do
        post profile_access_tokens_path, params: { name: "Claude", permission: "write" }
      end

      assert_response :success
      access_token = @user.access_tokens.last
      assert_equal "Claude", access_token.name
      assert access_token.write?

      token = response.body[/value="(#{AccessToken::PREFIX}\w+)"/, 1]
      assert_not_nil token
      assert_equal access_token, AccessToken.authenticate(token)

      get edit_profile_path(tab: "api")
      assert_not_includes response.body, token
    end

    test "create without a name shows the error" do
      assert_no_difference -> { AccessToken.count } do
        post profile_access_tokens_path, params: { name: "", permission: "read" }
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "can&#39;t be blank"
    end

    test "destroy revokes the token" do
      access_token = @user.access_tokens.create!(name: "Old")

      delete profile_access_token_path(access_token)

      assert_redirected_to edit_profile_path(tab: "api")
      assert_not AccessToken.exists?(access_token.id)
    end

    test "cannot revoke another user's token" do
      access_token = users(:two).access_tokens.create!(name: "Theirs")

      delete profile_access_token_path(access_token)

      assert AccessToken.exists?(access_token.id)
    end
  end
end

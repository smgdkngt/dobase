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

    test "the api tab shows how to install the command-line tool and sign in here" do
      get edit_profile_path(tab: "api")

      assert_includes response.body, "cli/install.sh | sh"
      assert_includes response.body, "dobase login http://www.example.com"
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

    test "create makes an agent token when asked" do
      post profile_access_tokens_path, params: { name: "Claude", permission: "write", agent: "true" }

      assert @user.access_tokens.last.agent?
      assert_includes response.body, "Agent"
    end

    test "update switches a token between posting as you and as itself" do
      access_token = @user.access_tokens.create!(name: "Claude", permission: "write")

      patch profile_access_token_path(access_token, agent: true)
      assert_response :success
      assert access_token.reload.agent?

      patch profile_access_token_path(access_token, agent: false)
      assert_not access_token.reload.agent?
    end

    test "cannot switch another user's token" do
      access_token = users(:two).access_tokens.create!(name: "Theirs")

      patch profile_access_token_path(access_token, agent: true)

      assert_not access_token.reload.agent?
    end

    test "a token can't make itself an agent" do
      access_token = @user.access_tokens.create!(name: "Claude", permission: "write")

      patch profile_access_token_path(access_token, agent: true), headers: api_headers(@user)

      assert_response :forbidden
      assert_not access_token.reload.agent?
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

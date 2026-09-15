# frozen_string_literal: true

require "test_helper"

class AccessTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "generates a prefixed token and stores only its digest" do
    access_token = @user.access_tokens.create!(name: "CLI")

    assert access_token.token.start_with?(AccessToken::PREFIX)
    assert_equal AccessToken.digest(access_token.token), access_token.token_digest
    assert_nil AccessToken.find(access_token.id).token
  end

  test "authenticate finds the token by its plaintext value" do
    access_token = @user.access_tokens.create!(name: "CLI")

    assert_equal access_token, AccessToken.authenticate(access_token.token)
    assert_nil AccessToken.authenticate("dobase_wrong")
    assert_nil AccessToken.authenticate("")
    assert_nil AccessToken.authenticate(nil)
  end

  test "defaults to read permission" do
    assert_equal "read", @user.access_tokens.create!(name: "CLI").permission
  end

  test "requires a name and a known permission" do
    access_token = @user.access_tokens.new(name: "", permission: "admin")

    assert_not access_token.valid?
    assert access_token.errors[:name].any?
    assert access_token.errors[:permission].any?
  end

  test "read tokens only allow safe request methods" do
    access_token = @user.access_tokens.create!(name: "CLI", permission: "read")

    assert access_token.allows?("GET")
    assert access_token.allows?("HEAD")
    assert_not access_token.allows?("POST")
    assert_not access_token.allows?("PATCH")
    assert_not access_token.allows?("DELETE")
  end

  test "write tokens allow every request method" do
    access_token = @user.access_tokens.create!(name: "CLI", permission: "write")

    %w[GET POST PATCH PUT DELETE].each { |method| assert access_token.allows?(method) }
  end

  test "record_usage writes at most once per minute" do
    access_token = @user.access_tokens.create!(name: "CLI")

    access_token.record_usage
    first_use = access_token.reload.last_used_at
    assert_not_nil first_use

    travel 30.seconds do
      access_token.record_usage
      assert_equal first_use, access_token.reload.last_used_at
    end

    travel 2.minutes do
      access_token.record_usage
      assert access_token.reload.last_used_at > first_use
    end
  end

  test "is destroyed with its user" do
    user = User.create!(first_name: "Token", last_name: "Owner", email_address: "token-owner@example.com", password: "password123")
    access_token = user.access_tokens.create!(name: "CLI")

    user.destroy!

    assert_not AccessToken.exists?(access_token.id)
  end
end

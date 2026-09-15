# frozen_string_literal: true

require "test_helper"

class AccessTokenAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "a valid token authenticates JSON requests" do
    get profile_path, headers: api_headers(@user)

    assert_response :success
    assert_equal @user.email_address, response.parsed_body["email_address"]
    assert_equal "write", response.parsed_body.dig("access_token", "permission")
  end

  test "an unknown token is rejected with 401" do
    get profile_path, headers: { "Authorization" => "Bearer dobase_nope", "Accept" => "application/json" }

    assert_response :unauthorized
    assert_equal "Invalid access token", response.parsed_body["error"]
    assert_match(/\ABearer/, response.headers["WWW-Authenticate"])
  end

  test "JSON requests without any credentials get 401 instead of a login redirect" do
    get profile_path, as: :json

    assert_response :unauthorized
    assert_equal "Authentication required", response.parsed_body["error"]
  end

  test "HTML requests without credentials still redirect to login" do
    get edit_profile_path

    assert_redirected_to new_session_path
  end

  test "a read-only token cannot make write requests" do
    headers = api_headers(@user, permission: "read")

    get tools_path, headers: headers
    assert_response :success

    post tools_path, params: { tool: { name: "Nope", tool_type: "boards" } }, headers: headers, as: :json
    assert_response :forbidden
    assert_equal "This access token is read-only", response.parsed_body["error"]
  end

  test "tokens only work on actions that allow them" do
    headers = api_headers(@user)

    patch profile_path, params: { user: { first_name: "Hijacked" } }, headers: headers, as: :json
    assert_response :forbidden
    assert_equal "User", @user.reload.first_name

    delete tool_path(tools(:project_board)), headers: headers, as: :json
    assert_response :forbidden
    assert Tool.exists?(tools(:project_board).id)
  end

  test "tokens cannot create more tokens" do
    headers = api_headers(@user)

    assert_no_difference -> { @user.access_tokens.count } do
      post profile_access_tokens_path, params: { name: "Another", permission: "write" }, headers: headers, as: :json
    end

    assert_response :forbidden
  end

  test "a token request ignores the session cookie" do
    sign_in_as users(:two)

    get profile_path, headers: api_headers(@user)

    assert_response :success
    assert_equal @user.email_address, response.parsed_body["email_address"]
  end

  test "token requests skip CSRF verification while cookie requests keep it" do
    with_forgery_protection do
      post tools_path, params: { tool: { name: "Via token", tool_type: "boards" } }, headers: api_headers(@user), as: :json
      assert_response :created

      sign_in_as @user
      post tools_path, params: { tool: { name: "Via cookie", tool_type: "boards" } }, as: :json
      assert_response :unprocessable_entity
      assert_not Tool.exists?(name: "Via cookie")
    end
  end

  test "records when a token was last used" do
    headers = api_headers(@user)
    access_token = @user.access_tokens.last
    assert_nil access_token.last_used_at

    get profile_path, headers: headers

    assert_not_nil access_token.reload.last_used_at
  end

  test "reading a tool with a token does not touch the user's last visit" do
    tool = tools(:project_board)
    collaborator = collaborators(:one_project_board)
    collaborator.update_column(:last_seen_at, 1.day.ago)
    @user.update_column(:last_visited_path, "/tools/#{tools(:my_docs).id}/docs")

    get tool_path(tool), headers: api_headers(@user)

    assert_response :success
    assert_equal "/tools/#{tools(:my_docs).id}/docs", @user.reload.last_visited_path
    assert collaborator.reload.last_seen_at < 1.hour.ago
  end

  private

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end

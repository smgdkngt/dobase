# frozen_string_literal: true

require "test_helper"

class Demo::JoinsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_demo_tool_types
    @visitor = in_demo_mode { Demo.create_visitor! }
    @marcus = Demo.teammates_of(@visitor).find_by!(first_name: "Marcus")
  end

  test "a link shows who you would join as" do
    in_demo_mode { get demo_join_path(Demo.join_token(@marcus)) }

    assert_response :success
    assert_select "h1", text: "Join Moonshot Snacks"
    assert_select "strong", text: "Marcus Rivera"
    assert_select "form[action='#{demo_joins_path}'] button", text: "Join as Marcus"
    assert_match "open the link in a private window", response.body
  end

  test "joining signs this window in as the teammate, in the team chat" do
    in_demo_mode do
      assert_difference -> { @marcus.sessions.count }, 1 do
        post demo_joins_path, params: { token: Demo.join_token(@marcus) }
      end
    end

    assert_redirected_to tool_path(@visitor.owned_tools.find_by!(name: "Team Chat"))
    assert cookies[:session_id].present?

    in_demo_mode { get edit_profile_path }
    assert_response :success
    assert_select "input[value='Marcus']"
  end

  test "someone signed in is told they would leave their own session" do
    sign_in_as @visitor

    in_demo_mode { get demo_join_path(Demo.join_token(@marcus)) }

    assert_response :success
    assert_match "You're signed in as Guest Visitor here", response.body
  end

  test "an expired link is refused" do
    token = Demo.join_token(@marcus)

    travel Demo::LIFETIME + 1.minute do
      in_demo_mode do
        get demo_join_path(token)
        assert_redirected_to new_session_path

        assert_no_difference -> { Session.count } do
          post demo_joins_path, params: { token: token }
        end
      end
    end
    assert_redirected_to new_session_path
  end

  test "a tampered link is refused" do
    in_demo_mode do
      assert_no_difference -> { Session.count } do
        post demo_joins_path, params: { token: "#{Demo.join_token(@marcus)}x" }
      end
    end

    assert_redirected_to new_session_path
  end

  test "only a teammate can be joined as, not a visitor or anyone with an account" do
    in_demo_mode do
      [ @visitor, users(:one) ].each do |user|
        assert_no_difference -> { Session.count } do
          post demo_joins_path, params: { token: Demo.join_token(user) }
        end
        assert_redirected_to new_session_path

        get demo_join_path(Demo.join_token(user))
        assert_redirected_to new_session_path
      end
    end
  end

  test "a link made for something else doesn't join" do
    in_demo_mode do
      post demo_joins_path, params: { token: @marcus.signed_id(purpose: :password_reset) }
    end

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id].presence
  end

  test "there is nothing to join outside demo mode" do
    get demo_join_path(Demo.join_token(@marcus))
    assert_response :not_found

    assert_no_difference -> { Session.count } do
      post demo_joins_path, params: { token: Demo.join_token(@marcus) }
    end
    assert_response :not_found
  end
end

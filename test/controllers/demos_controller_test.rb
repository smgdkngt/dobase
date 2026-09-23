# frozen_string_literal: true

require "test_helper"

class DemosControllerTest < ActionDispatch::IntegrationTest
  setup { create_demo_tool_types }

  test "a visitor gets a workspace of their own and is signed in to it" do
    in_demo_mode do
      assert_difference -> { Demo.visitors.count }, 1 do
        post demo_path
      end

      visitor = Demo.visitors.last
      board = visitor.owned_tools.find_by!(name: "Product Launch")
      assert_redirected_to tool_path(board)
      assert cookies[:session_id].present?
      assert_equal 12, visitor.owned_tools.count

      follow_redirect!
      follow_redirect!
      assert_response :success
      assert_select ".demo-banner", text: /You're trying the .* demo/
    end
  end

  test "someone signed in already goes back to their workspace" do
    sign_in_as users(:one)

    in_demo_mode do
      assert_no_difference -> { User.count } do
        post demo_path
      end
    end

    assert_redirected_to root_path
  end

  test "a full demo asks visitors to come back later" do
    in_demo_mode do
      stub_const(Demo, :MAX_VISITORS, 0) do
        assert_no_difference "User.count" do
          post demo_path
        end
      end
    end

    assert_redirected_to new_session_path
    assert_match "busy", flash[:alert]
  end

  test "there is no demo outside demo mode" do
    assert_no_difference -> { User.count } do
      post demo_path
    end

    assert_response :not_found
  end

  test "the sign-in page offers the demo in demo mode only" do
    get new_session_path
    assert_select "form[action='#{demo_path}']", count: 0

    in_demo_mode { get new_session_path }
    assert_select "form[action='#{demo_path}'] button", text: "Try the demo"
    assert_select "a[href='#{signup_path}']", count: 0
  end

  test "signed-in pages show the demo banner in demo mode only" do
    sign_in_as users(:one)

    get tool_files_path(tools(:my_files))
    assert_select ".demo-banner", count: 0

    in_demo_mode do
      get tool_files_path(tools(:my_files))
      assert_select ".demo-banner a[href='https://github.com/smgdkngt/dobase']", text: "Get Dobase"
    end
  end
end

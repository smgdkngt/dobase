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

class DemosControllerTogetherTest < ActionDispatch::IntegrationTest
  setup { create_demo_tool_types }

  test "the banner offers links to join as each of your teammates" do
    in_demo_mode do
      post demo_path
      visitor = Demo.visitors.last
      get tool_path(visitor.owned_tools.find_by!(name: "Team Chat"))
      follow_redirect!

      assert_select ".demo-banner button[popovertarget='demo-together']", text: "Try it together"
      assert_select "#demo-together[popover] .demo-together-person", count: 3
      assert_equal Demo.teammates_of(visitor).order(:id).to_a, joinable_from_banner
    end
  end

  test "a teammate's banner offers the other teammates, not the visitor" do
    visitor = in_demo_mode { Demo.create_visitor! }
    marcus, priya, jake = Demo.teammates_of(visitor).order(:id).to_a

    in_demo_mode do
      post demo_joins_path, params: { token: Demo.join_token(marcus) }
      follow_redirect!
      follow_redirect!

      assert_select ".demo-banner", text: /You're trying the .* demo/
      assert_select "#demo-together .demo-together-name", text: /\A(Priya Patel|Jake Thompson)\z/, count: 2
      assert_equal [ priya, jake ], joinable_from_banner
    end
  end

  test "someone outside a demo party gets no links to share" do
    sign_in_as users(:one)

    in_demo_mode { get tool_files_path(tools(:my_files)) }

    assert_select ".demo-banner"
    assert_select "#demo-together", count: 0
  end

  private

  # Whom the links in the banner join as
  def joinable_from_banner
    css_select("#demo-together input[type=hidden]").map do |input|
      token = input["value"].delete_prefix(demo_joins_url + "/")
      User.find_signed(token, purpose: :demo_join)
    end
  end
end

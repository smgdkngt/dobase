# frozen_string_literal: true

require "test_helper"

module SidebarGroups
  class MembershipsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @shared = tools(:shared_board)
      @group = users(:one).sidebar_groups.create!(name: "Work", position: 0)
    end

    test "grouping a shared tool leaves it where the other collaborator put it" do
      sign_in_as users(:one)

      post sidebar_group_memberships_path(@group), params: { tool_id: @shared.id }

      assert_response :redirect
      assert_equal [ @shared ], @group.reload.tools.to_a
      assert_not_includes users(:one).ungrouped_tools, @shared
      assert_includes users(:two).ungrouped_tools, @shared
    end

    test "moving a tool from one group to another only touches the mover's sidebar" do
      other_group = users(:one).sidebar_groups.create!(name: "Later", position: 1)
      twos_group = users(:two).sidebar_groups.create!(name: "Theirs", position: 0)
      twos_group.memberships.create!(tool: @shared, position: 0)

      sign_in_as users(:one)
      post sidebar_group_memberships_path(@group), params: { tool_id: @shared.id }
      post sidebar_group_memberships_path(other_group), params: { tool_id: @shared.id }

      assert_empty @group.reload.tools
      assert_equal [ @shared ], other_group.reload.tools.to_a
      assert_equal [ @shared ], twos_group.reload.tools.to_a
    end

    test "ungrouping a tool returns it to your own ungrouped list only" do
      @group.memberships.create!(tool: @shared, position: 0)
      sign_in_as users(:one)

      delete sidebar_group_membership_path(@group, @shared)

      assert_empty @group.reload.tools
      assert_includes users(:one).ungrouped_tools, @shared
    end

    test "a tool you cannot access cannot be grouped" do
      sign_in_as users(:one)

      post sidebar_group_memberships_path(@group), params: { tool_id: tools(:other_mail).id }

      assert_redirected_to root_path
      assert_empty @group.reload.tools
    end
  end
end

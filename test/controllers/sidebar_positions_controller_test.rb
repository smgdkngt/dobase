# frozen_string_literal: true

require "test_helper"

class SidebarPositionsControllerTest < ActionDispatch::IntegrationTest
  test "reordering your sidebar leaves the sidebar of a collaborator on the same tool alone" do
    order_for_two = users(:two).ungrouped_tools.to_a

    sign_in_as users(:one)
    reversed = users(:one).ungrouped_tools.to_a.reverse
    reorder reversed

    assert_response :success
    assert_equal reversed, users(:one).ungrouped_tools.to_a
    assert_equal order_for_two, users(:two).ungrouped_tools.to_a
  end

  test "two collaborators each keep their own order of the same tool" do
    shared = tools(:shared_board)

    sign_in_as users(:one)
    reorder [ shared ] + (users(:one).ungrouped_tools.to_a - [ shared ])

    sign_in_as users(:two)
    reorder (users(:two).ungrouped_tools.to_a - [ shared ]) + [ shared ]

    assert_equal shared, users(:one).ungrouped_tools.first
    assert_equal shared, users(:two).ungrouped_tools.last
  end

  test "the order survives a reload of the sidebar" do
    sign_in_as users(:one)
    reversed = users(:one).ungrouped_tools.to_a.reverse
    reorder reversed

    get tools_path

    assert_response :success
    assert_equal reversed, users(:one).reload.ungrouped_tools.to_a
  end

  test "reordering never touches a tool the user has no access to" do
    sign_in_as users(:one)

    assert_no_changes -> { users(:two).collaborations.find_by(tool: tools(:other_mail)).sidebar_position } do
      reorder [ tools(:other_mail), tools(:my_docs) ]
    end
  end

  test "reordering without ids is rejected" do
    sign_in_as users(:one)

    patch sidebar_positions_path

    assert_response :unprocessable_entity
  end

  private

  def reorder(tools)
    patch sidebar_positions_path, params: { tool_ids: tools.map(&:id) }
  end
end

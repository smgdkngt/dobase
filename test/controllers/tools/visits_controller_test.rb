# frozen_string_literal: true

require "test_helper"

class Tools::VisitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tool = tools(:project_board)
    sign_in_as @user
  end

  test "a visit says the tool was seen as it is now" do
    collaborator = @tool.collaborators.find_by!(user: @user)
    collaborator.update_column(:last_seen_at, 2.days.ago)

    post tool_visit_path(@tool)

    assert_response :no_content
    assert_in_delta Time.current, collaborator.reload.last_seen_at, 5.seconds
  end

  test "only for a tool you have" do
    sign_in_as users(:two)
    tool = Tool.create!(name: "Not yours", tool_type: tool_types(:todos), owner: @user)

    post tool_visit_path(tool)

    assert_redirected_to root_path
    assert_nil tool.collaborators.find_by(user: users(:two))
  end

  test "a token can't say it" do
    post tool_visit_path(@tool), headers: api_headers(@user)

    assert_response :forbidden
  end
end

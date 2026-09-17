# frozen_string_literal: true

require "test_helper"

class ToolsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "index runs the same number of queries however many tools the user has" do
    add_tools = -> do
      3.times { |index| Tool.create!(name: "Owned #{index}", tool_type: tool_types(:docs), owner: users(:one)) }
      shared = Tool.create!(name: "Shared", tool_type: tool_types(:docs), owner: users(:two))
      shared.collaborators.create!(user: users(:one), role: "collaborator")
    end

    assert_queries_independent_of(add_tools) { get tools_path }
  end

  test "index offers settings only on the tools the user owns" do
    shared = Tool.create!(name: "Someone else's", tool_type: tool_types(:docs), owner: users(:two))
    shared.collaborators.create!(user: users(:one), role: "collaborator")

    get tools_path

    assert_response :success
    assert_select "div", text: /Someone else.s\s*Docs\s*Shared/
    assert_select "span", text: "Owner", count: users(:one).accessible_tools.count { |tool| tool.owned_by?(users(:one)) }
  end
end

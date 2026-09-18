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

  test "every label on the new tool page, which renders the add tool modal too, has a field of its own" do
    get new_tool_path

    assert_response :success
    assert_labels_point_at_their_own_fields
  end

  test "every label in the tool settings has a field of its own" do
    get edit_tool_path(tools(:project_board)), headers: { "Turbo-Frame" => "edit-tool-form" }

    assert_response :success
    assert_labels_point_at_their_own_fields
  end

  private

  # A label's `for` has to name exactly one field on the page: none means the label
  # does nothing, more than one means it may point at the wrong field.
  def assert_labels_point_at_their_own_fields
    labels = css_select("label[for]")
    assert_operator labels.size, :>=, 1

    labels.each do |label|
      assert_select "##{label["for"]}", count: 1, message: "label for=#{label["for"]} doesn't name exactly one field"
    end

    ids = css_select("input[id], select[id], textarea[id]").map { |field| field["id"] }
    assert_equal ids.uniq, ids, "the page has fields sharing an id"
  end
end

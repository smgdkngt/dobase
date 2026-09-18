# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
    sign_in_as @user
  end

  test "redirects to a navigational last visited tool path" do
    path = tool_files_path(@tool)
    @user.update_column(:last_visited_path, path)

    get root_path

    assert_redirected_to path
  end

  test "does not redirect to a stored download path and clears it" do
    download_path = "/tools/#{@tool.id}/files/items/#{file_items(:readme).id}/download"
    @user.update_column(:last_visited_path, download_path)

    get root_path

    assert_response :redirect
    refute_equal download_path, response.location.sub(%r{\Ahttps?://[^/]+}, "")
    assert_nil @user.reload.last_visited_path
  end

  test "clears a last visited path for a tool that is no longer accessible" do
    @user.update_column(:last_visited_path, "/tools/#{tools(:other_calendar).id}/calendar")

    get root_path

    assert_response :redirect
    assert_nil @user.reload.last_visited_path
  end

  test "a last visited path whose record is gone doesn't bounce the dashboard back and forth" do
    document = Docs::Document.create!(tool: tools(:my_docs), title: "Notes", created_by: @user)
    get tool_docs_document_path(tools(:my_docs), document)
    assert_equal tool_docs_document_path(tools(:my_docs), document), @user.reload.last_visited_path

    document.destroy!

    get root_path
    follow_redirect!

    assert_nil @user.reload.last_visited_path
    follow_redirect!
    assert_no_match %r{/documents/#{document.id}\z}, response.location.to_s
  end
end

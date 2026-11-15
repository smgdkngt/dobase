# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
    sign_in_as @user
    # The start page for one tool, as a phone gets it: for a wide window it is the
    # workspace (WorkspaceTest). The cookie is the tests' own way to ask for it.
    cookies[:workspace] = "off"
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

  test "a draft's JSON asked for by the compose page is never the page to come back to" do
    tool = tools(:my_mail)
    draft = mails_messages(:draft_message)
    get tool_files_path(@tool)

    get tool_mail_path(tool, draft, format: :json), headers: { "Accept" => "application/json" }
    assert_response :success

    assert_equal tool_files_path(@tool), @user.reload.last_visited_path
  end

  test "does not redirect to a stored JSON path, which it clears" do
    json_path = "/tools/#{@tool.id}/mails/26322.json"
    @user.update_column(:last_visited_path, json_path)

    get root_path

    assert_response :redirect
    refute_equal json_path, response.location.sub(%r{\Ahttps?://[^/]+}, "")
    assert_nil @user.reload.last_visited_path
  end

  test "a message for the start page reaches the page it sends you on to" do
    tool = Tool.create!(name: "Scratch", tool_type: tool_types(:docs), owner: @user)

    delete tool_path(tool)
    follow_redirect! while response.redirect?

    assert_response :success
    assert_select "#flash .flash", text: /Scratch deleted successfully/
  end

  test "a message for the start page reaches the workspace" do
    cookies[:workspace] = "on"

    get invitation_acceptance_path(token: "no-such-token")
    follow_redirect! while response.redirect?

    assert_equal workspace_path, path
    assert_select "#flash .flash", text: /Invalid invitation link/
  end

  test "a message on a tool's page goes along when a wide window takes that page to the workspace" do
    cookies[:workspace] = "on"
    invitation = tools(:shared_board).invitations.create!(email: "newcomer@example.com", invited_by: users(:two))
    newcomer = User.create!(first_name: "New", last_name: "Comer", email_address: "newcomer@example.com", password: "password")
    sign_in_as newcomer

    post invitation_acceptance_path(token: invitation.token)
    follow_redirect! while response.redirect?

    assert_select "script[data-wide][data-flash]" do |scripts|
      assert_includes scripts.first["data-flash"], "You are now a collaborator on"
    end
  end
end

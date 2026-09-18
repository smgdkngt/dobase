# frozen_string_literal: true

require "test_helper"

module Tools
  class DocsApiTest < ActionDispatch::IntegrationTest
    include ActionCable::TestHelper

    setup do
      @user = users(:one)
      @other_user = users(:two)
      @headers = api_headers(@user)
      @tool = tools(:my_docs)
      @tool.collaborators.create!(user: @other_user, role: "collaborator")
      @document = docs_documents(:meeting_notes)
    end

    test "docs lists documents with a preview, word count and who edited them" do
      @document.update!(content: "<p>Agenda: ship the <strong>API</strong> today</p>", updated_by: @other_user)

      get tool_docs_path(@tool), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal tool_docs_url(@tool), body["url"]
      assert_equal [ "Meeting Notes", "Empty Document", "Project Plan" ], body["documents"].map { |document| document["title"] }

      document = body["documents"].first
      assert_equal "Agenda: ship the API today", document["preview"]
      assert_equal @other_user.email_address, document.dig("updated_by", "email_address")
      assert_equal false, document["locked"]
      assert_nil document["locked_by"]
      assert_equal tool_docs_document_url(@tool, @document), document["url"]
      assert_not document.key?("content")
    end

    test "docs shows who is editing while the lock is live" do
      @document.update_columns(locked_by_id: @other_user.id, locked_at: 1.minute.ago)
      docs_documents(:project_plan).update_columns(locked_by_id: @other_user.id, locked_at: 10.minutes.ago)

      get tool_docs_path(@tool), headers: @headers

      documents = response.parsed_body["documents"].index_by { |document| document["title"] }
      assert documents["Meeting Notes"]["locked"]
      assert_equal @other_user.name, documents.dig("Meeting Notes", "locked_by", "name")
      assert_not documents["Project Plan"]["locked"]
      assert_nil documents["Project Plan"]["locked_by"]
    end

    test "docs doesn't remember a view mode for JSON requests" do
      get tool_docs_path(@tool, view: "list"), headers: @headers

      assert_response :success
      assert_nil response.cookies["docs_view"]
    end

    test "docs is forbidden for tools the user can't access" do
      get tool_docs_path(@tool), headers: api_headers(users(:with_otp))

      assert_response :forbidden
    end

    test "document shows its content as text and HTML" do
      @document.update!(content: "<h1>Notes</h1><p>Hello <em>team</em></p>")

      get tool_docs_document_path(@tool, @document), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal "Meeting Notes", body["title"]
      assert_includes body["content"], "Hello team"
      assert_includes body["content_html"], "<em>team</em>"
      assert_equal @user.email_address, body.dig("creator", "email_address")
    end

    test "plain-text content keeps headings on their own line" do
      @document.update!(content: "<h2>Brand voice</h2><p>Fun and adventurous</p>")

      get tool_docs_document_path(@tool, @document), headers: @headers

      assert_equal "Brand voice\n\nFun and adventurous", response.parsed_body["content"]
    end

    test "document from another docs tool is not found" do
      other_tool = Tool.create!(name: "Other Docs", owner: @user, tool_type: tool_types(:docs))

      get tool_docs_document_path(other_tool, @document), headers: @headers
      assert_response :not_found

      patch tool_docs_document_path(other_tool, @document), params: { docs_document: { title: "Moved" } }, headers: @headers, as: :json
      assert_response :not_found
      assert_equal "Meeting Notes", @document.reload.title
    end

    test "create makes a document with a title and content and notifies collaborators" do
      assert_difference -> { @other_user.notifications.count }, 1 do
        post tool_docs_documents_path(@tool), headers: @headers, as: :json, params: {
          docs_document: { title: "Launch plan", content: "<p>Step <strong>one</strong></p>" }
        }
      end

      assert_response :created
      body = response.parsed_body
      assert_equal "Launch plan", body["title"]
      assert_equal "Step one", body["content"]
      assert_includes body["content_html"], "<strong>one</strong>"
      assert_equal @user.id, body.dig("creator", "id")

      document = ::Docs::Document.find(body["id"])
      assert_equal @tool, document.tool
      assert_nil document.locked_by
    end

    test "create without attributes makes an untitled document" do
      post tool_docs_documents_path(@tool), params: { docs_document: { content: "<p>Draft</p>" } }, headers: @headers, as: :json

      assert_response :created
      assert_equal "Untitled", response.parsed_body["title"]
    end

    test "create with a blank title returns errors" do
      assert_no_difference -> { ::Docs::Document.count } do
        post tool_docs_documents_path(@tool), params: { docs_document: { title: "" } }, headers: @headers, as: :json
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Title can't be blank"
    end

    test "update changes the title and content and broadcasts the change" do
      assert_broadcasts DocumentChannel.broadcasting_for(@document), 1 do
        patch tool_docs_document_path(@tool, @document), headers: @headers, as: :json, params: {
          docs_document: { title: "Weekly notes", content: "<p>Updated</p>" }
        }
      end

      assert_response :success
      assert_equal "Weekly notes", response.parsed_body["title"]
      assert_equal "Updated", response.parsed_body["content"]
      assert_equal "Updated", @document.reload.content.to_plain_text
      assert_equal @user, @document.updated_by
    end

    test "update with a blank title returns errors" do
      patch tool_docs_document_path(@tool, @document), params: { docs_document: { title: "" } }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Title can't be blank"
    end

    test "update is refused while someone else is editing" do
      @document.update_columns(locked_by_id: @other_user.id, locked_at: 1.minute.ago)

      patch tool_docs_document_path(@tool, @document), params: { docs_document: { content: "<p>Overwrite</p>" } }, headers: @headers, as: :json

      assert_response :conflict
      assert_equal "User Two is editing this document", response.parsed_body["error"]
      assert_equal "", @document.reload.content.to_plain_text
    end

    test "destroy is refused while someone else is editing" do
      @document.update_columns(locked_by_id: @other_user.id, locked_at: 1.minute.ago)

      delete tool_docs_document_path(@tool, @document), headers: @headers, as: :json

      assert_response :conflict
      assert ::Docs::Document.exists?(@document.id)
    end

    test "update goes through once the other editor's lock has expired" do
      @document.update_columns(locked_by_id: @other_user.id, locked_at: 10.minutes.ago)

      patch tool_docs_document_path(@tool, @document), params: { docs_document: { content: "<p>Mine now</p>" } }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Mine now", @document.reload.content.to_plain_text
    end

    test "the lock holder can still save through the API" do
      @document.update_columns(locked_by_id: @user.id, locked_at: 1.minute.ago)

      patch tool_docs_document_path(@tool, @document), params: { docs_document: { content: "<p>Still mine</p>" } }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Still mine", @document.reload.content.to_plain_text
    end

    test "the editor's autosave keeps working while someone else is writing too" do
      @document.update_columns(locked_by_id: @user.id, locked_at: 1.minute.ago)
      sign_in_as @other_user
      get edit_tool_docs_document_path(@tool, @document)
      assert_response :success

      patch tool_docs_document_path(@tool, @document),
        params: { docs_document: { title: "Autosaved", content: "<p>Typing</p>" } },
        headers: { "Accept" => "application/json" }

      assert_response :success
      assert_equal "Autosaved", @document.reload.title
      assert_equal "Typing", @document.content.to_plain_text
    end

    test "destroy returns no content" do
      delete tool_docs_document_path(@tool, @document), headers: @headers, as: :json

      assert_response :no_content
      assert_not ::Docs::Document.exists?(@document.id)
    end

    test "tokens can't open the editor or take the lock" do
      get edit_tool_docs_document_path(@tool, @document), headers: @headers

      assert_response :forbidden
      assert_nil @document.reload.locked_by_id
    end

    test "read-only tokens can read documents but not change them" do
      headers = api_headers(@user, permission: "read")

      get tool_docs_path(@tool), headers: headers
      assert_response :success

      get tool_docs_document_path(@tool, @document), headers: headers
      assert_response :success

      assert_no_difference -> { ::Docs::Document.count } do
        post tool_docs_documents_path(@tool), params: { docs_document: { title: "Nope" } }, headers: headers, as: :json
      end
      assert_response :forbidden

      patch tool_docs_document_path(@tool, @document), params: { docs_document: { title: "Nope" } }, headers: headers, as: :json
      assert_response :forbidden

      delete tool_docs_document_path(@tool, @document), headers: headers, as: :json
      assert_response :forbidden
      assert_equal "Meeting Notes", @document.reload.title
    end
  end
end

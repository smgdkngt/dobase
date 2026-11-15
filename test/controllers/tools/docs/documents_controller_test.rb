# frozen_string_literal: true

require "test_helper"

module Tools
  module Docs
    class DocumentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_docs)
      end

      test "create creates new document and redirects to edit" do
        assert_difference "::Docs::Document.count", 1 do
          post tool_docs_documents_path(@tool)
        end

        document = ::Docs::Document.last
        assert_redirected_to edit_tool_docs_document_path(@tool, document)
        assert_equal "Untitled", document.title
        assert_equal @tool, document.tool
      end

      test "an empty document still has somewhere for a live edit to land" do
        get tool_docs_document_path(@tool, docs_documents(:empty_document))

        assert_response :success
        assert_select "[data-document-viewer-target=content]"
        assert_select "[data-document-viewer-target=content]", text: /This document is empty/
      end

      test "saving a document without changing it leaves who edited it last, and when" do
        document = docs_documents(:meeting_notes)
        document.update!(content: "<p>As it was</p>")
        yesterday = 1.day.ago.change(usec: 0)
        document.update_columns(updated_by_id: users(:two).id, last_edited_at: yesterday, updated_at: yesterday)

        patch tool_docs_document_path(@tool, document), params: { docs_document: { title: document.title, content: document.content.body.to_html } }, as: :json

        assert_response :success
        document.reload
        assert_equal [ users(:two), yesterday, yesterday ], [ document.updated_by, document.last_edited_at, document.updated_at ]
      end

      test "saving a changed text records who edited it" do
        document = docs_documents(:meeting_notes)
        document.update_columns(updated_by_id: users(:two).id, last_edited_at: 1.day.ago)

        patch tool_docs_document_path(@tool, document), params: { docs_document: { title: document.title, content: "<p>New words</p>" } }, as: :json

        assert_response :success
        assert_equal users(:one), document.reload.updated_by
        assert_in_delta Time.current, document.last_edited_at, 5
      end

      test "requires authentication" do
        sign_out

        assert_no_difference "::Docs::Document.count" do
          post tool_docs_documents_path(@tool)
        end

        assert_redirected_to new_session_path
      end
    end
  end
end
